import CoreModels
import Foundation
import GitHubAPI
import Observation
import SecurityKit

@MainActor @Observable
final class WorkflowJobLogModel {
    private(set) var snapshot: WorkflowJobLogSnapshot?
    private(set) var error: WorkflowJobLogLoadError?
    private(set) var isLoading = false
    @ObservationIgnored private let loader: GitHubJobLogLoader
    @ObservationIgnored private let secrets: any SecretReading
    @ObservationIgnored private let rateBudget: WorkflowHistoryRateBudget
    @ObservationIgnored private var selection: WorkflowJobLogSelection?
    @ObservationIgnored private var generation = 0

    init(loader: GitHubJobLogLoader = GitHubJobLogLoader(), secrets: any SecretReading = KeychainVaultActor(),
         rateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget()) {
        self.loader = loader; self.secrets = secrets; self.rateBudget = rateBudget
    }

    func select(_ selection: WorkflowJobLogSelection) {
        guard self.selection != selection else { return }
        invalidate(); self.selection = selection; snapshot = nil; error = nil
    }
    func invalidate() { generation += 1; isLoading = false }

    func loadJobLog(selection: WorkflowJobLogSelection) async {
        guard self.selection == selection, !isLoading, !Task.isCancelled else { return }
        let account = selection.detail.source.accountID
        let source = selection.detail.source
        guard account > 0, selection.detail.runID > 0, selection.detail.attempt > 0, selection.jobID > 0 else {
            error = .unavailable; return
        }
        guard (rateBudget.deadline(for: account) ?? .distantPast) <= .now else { error = .rateLimited; return }
        let ticket = generation
        isLoading = true; error = nil
        defer { if ticket == generation { isLoading = false } }
        do {
            guard !source.keychainAccountKey.isEmpty,
                  let token = try await secrets.readSecret(account: source.keychainAccountKey, category: "github-oauth"), !token.isEmpty else {
                throw WorkflowHistoryLoadError.authenticationRequired
            }
            guard ticket == generation, !Task.isCancelled else { return }
            let loaded = try await loader.load(repository: source.repository, jobID: selection.jobID, token: token)
            observe(loaded.rateLimit, account: account)
            guard ticket == generation, !Task.isCancelled else { return }
            snapshot = loaded.snapshot
        } catch {
            let failure: WorkflowJobLogLoadError
            switch error {
            case WorkflowHistoryLoadError.authenticationRequired: failure = .authenticationRequired
            case GitHubActionsError.httpStatus(401, _): failure = .authenticationRequired
            case GitHubActionsError.httpStatus(let status, let rate) where status == 429 || (status == 403 && (rate?.remaining == 0 || rate?.retryAfterSeconds != nil)):
                rateBudget.observe(rate, accountID: account)
                let retry = rate?.retryAfterSeconds.map { Date.now.addingTimeInterval(Double($0)) }
                let reset = rate?.remaining == 0 ? rate?.resetAt : nil
                rateBudget.recordLimit(until: [retry, reset].compactMap { $0 }.max(), accountID: account, now: .now)
                failure = .rateLimited
            case GitHubActionsError.httpStatus(403, _): failure = .permissionDenied
            case GitHubActionsError.httpStatus(404, _), GitHubActionsError.httpStatus(410, _): failure = .notAvailable
            case let logError as GitHubJobLogError:
                observe(logError.rateLimit, account: account)
                switch logError {
                case .unsupportedContent: failure = .unsupportedContent
                case .downloadFailed(let status, _) where status == 403 || status == 404 || status == 410: failure = .notAvailable
                default: failure = .unavailable
                }
            default: failure = .unavailable
            }
            guard ticket == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = failure
        }
    }
    private func observe(_ rate: GitHubRateLimitSnapshot?, account: Int64) {
        rateBudget.observe(rate, accountID: account)
        if rate?.remaining == 0 {
            rateBudget.recordLimit(until: rate?.resetAt, accountID: account, now: .now)
        }
    }
}
