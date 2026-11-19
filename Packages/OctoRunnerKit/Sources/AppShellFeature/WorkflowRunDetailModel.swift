import Foundation
import GitHubAPI
import Observation
import SecurityKit

@MainActor
@Observable
final class WorkflowRunDetailModel {
    private(set) var jobs: [GitHubWorkflowJobDTO] = []
    private(set) var observedAt: Date?
    private(set) var isLoading = false
    private(set) var error: WorkflowHistoryLoadError?
    @ObservationIgnored private let client: GitHubActionsClient
    @ObservationIgnored private let secrets: any SecretReading
    @ObservationIgnored private let rateBudget: WorkflowHistoryRateBudget
    @ObservationIgnored private var selection: WorkflowRunDetailSelection?
    @ObservationIgnored private var generation = 0

    init(client: GitHubActionsClient = GitHubActionsClient(), secrets: any SecretReading = KeychainVaultActor(),
         rateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget()) {
        self.client = client; self.secrets = secrets; self.rateBudget = rateBudget
    }

    func select(_ selection: WorkflowRunDetailSelection?) {
        invalidate()
        self.selection = selection
        jobs = []; observedAt = nil; error = nil
    }

    func invalidate() { generation += 1; isLoading = false }

    func load() async {
        guard let selection, !isLoading, !Task.isCancelled else { return }
        let ticket = generation
        let account = selection.source.accountID
        guard (rateBudget.deadline(for: account) ?? .distantPast) <= .now else {
            error = .rateLimited(until: rateBudget.deadline(for: account)); return
        }
        isLoading = true; error = nil
        defer { if ticket == generation { isLoading = false } }
        do {
            guard account > 0, !selection.source.keychainAccountKey.isEmpty,
                  let token = try await secrets.readSecret(account: selection.source.keychainAccountKey, category: "github-oauth"), !token.isEmpty else {
                throw WorkflowHistoryLoadError.authenticationRequired
            }
            guard ticket == generation, !Task.isCancelled else { return }
            var all: [GitHubWorkflowJobDTO] = []
            var next: URL?
            var visited = Set<URL>()
            var pages = 0
            var expectedTotal: Int?
            repeat {
                guard pages < 20 else { throw WorkflowHistoryLoadError.tooManyPages }
                let page = try await client.workflowJobs(repository: selection.source.repository, runID: selection.runID,
                    attempt: selection.attempt, token: token, page: next)
                rateBudget.observe(page.rateLimit, accountID: account)
                if page.rateLimit?.remaining == 0 {
                    rateBudget.recordLimit(until: page.rateLimit?.resetAt, accountID: account, now: .now)
                }
                guard ticket == generation, !Task.isCancelled else { return }
                guard page.totalCount >= 0, expectedTotal == nil || expectedTotal == page.totalCount else {
                    throw WorkflowHistoryLoadError.unavailable
                }
                expectedTotal = page.totalCount
                all.append(contentsOf: page.items)
                next = page.nextPage
                pages += 1
                if let next {
                    guard page.rateLimit?.remaining != 0 else { throw WorkflowHistoryLoadError.rateLimited(until: rateBudget.deadline(for: account)) }
                    guard visited.insert(next).inserted else { throw WorkflowHistoryLoadError.tooManyPages }
                }
            } while next != nil
            guard all.count == expectedTotal, Set(all.map(\.id)).count == all.count else {
                throw WorkflowHistoryLoadError.unavailable
            }
            guard ticket == generation, !Task.isCancelled else { return }
            jobs = all; observedAt = .now
        } catch {
            let failure: WorkflowHistoryLoadError
            if let apiError = error as? GitHubActionsError {
                switch apiError {
                case .httpStatus(401, _): failure = .authenticationRequired
                case .httpStatus(let status, let rate) where status == 429 || (status == 403 && (rate?.remaining == 0 || rate?.retryAfterSeconds != nil)):
                    rateBudget.observe(rate, accountID: account)
                    let retry = rate?.retryAfterSeconds.map { Date.now.addingTimeInterval(Double($0)) }
                    let reset = rate?.remaining == 0 ? rate?.resetAt : nil
                    rateBudget.recordLimit(until: [retry, reset].compactMap { $0 }.max(), accountID: account, now: .now)
                    failure = .rateLimited(until: rateBudget.deadline(for: account))
                case .httpStatus(403, _): failure = .permissionDenied
                default: failure = .unavailable
                }
            } else { failure = error as? WorkflowHistoryLoadError ?? .unavailable }
            guard ticket == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            self.error = failure
        }
    }
}
