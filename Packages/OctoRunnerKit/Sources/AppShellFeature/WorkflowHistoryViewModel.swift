import CoreModels
import Foundation
import GitHubAPI
import Observation
import SwiftData

@MainActor
@Observable
public final class WorkflowHistoryViewModel {
    public private(set) var entries: [WorkflowHistoryEntry] = []
    public private(set) var isLoading = false
    public private(set) var error: WorkflowHistoryLoadError?
    public private(set) var nextPage: URL?
    public private(set) var rateLimit: GitHubRateLimitSnapshot?
    public private(set) var lastRefresh: Date?

    public private(set) var repositoryFailures: [WorkflowHistoryRepositoryFailure] = []
    private let rateBudget: WorkflowHistoryRateBudget
    private let loader: any WorkflowHistoryLoading
    private var selection: WorkflowHistorySelection?
    private var generation = 0
    private var hasLoadedPage = false

    public var retryNotBefore: Date? {
        selection.flatMap { rateBudget.deadline(for: $0.accountID) }
    }

    public init(loader: any WorkflowHistoryLoading = GitHubWorkflowHistoryLoader(), rateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget()) {
        self.loader = loader
        self.rateBudget = rateBudget
    }

    public func select(_ selection: WorkflowHistorySelection?, in context: ModelContext) throws {
        invalidate()
        self.selection = selection
        nextPage = nil
        rateLimit = nil
        error = nil
        repositoryFailures = []
        lastRefresh = nil
        hasLoadedPage = false
        entries = []
        try reloadEntries(in: context)
    }

    public func invalidate() {
        generation += 1
        isLoading = false
    }

    /// Refresh a bounded recent window for each configured repository. All sources
    /// belong to one credential; account changes and cancellation end the batch.
    public func refreshRepositories(_ selections: [WorkflowHistorySelection], in context: ModelContext) async {
        guard !Task.isCancelled else { return }
        guard let first = selections.first, selections.allSatisfy({
            $0.accountID == first.accountID && $0.keychainAccountKey == first.keychainAccountKey
        }) else {
            do { try select(nil, in: context) } catch { self.error = .unavailable }
            return
        }
        var failures: [WorkflowHistoryRepositoryFailure] = []
        for source in selections {
            guard !Task.isCancelled else { return }
            do { try select(source, in: context) }
            catch { self.error = .unavailable; return }
            repositoryFailures = failures
            let batchGeneration = generation
            await load(in: context, refresh: true)
            guard isCurrent(batchGeneration, selection: source) else { return }
            if let error {
                switch error {
                case .authenticationRequired, .rateLimited: return
                case .permissionDenied, .tooManyPages, .unavailable:
                    failures.append(WorkflowHistoryRepositoryFailure(repository: source.repository, error: error))
                    repositoryFailures = failures
                    self.error = nil
                }
            }
            if let deadline = retryNotBefore, deadline > .now { return }
        }
    }

    public func load(in context: ModelContext, refresh: Bool = false, now: Date? = nil) async {
        guard !Task.isCancelled, let selection, !isLoading, refresh || !hasLoadedPage || nextPage != nil else { return }
        if let deadline = retryNotBefore, deadline > (now ?? .now) { return }
        let currentGeneration = generation
        isLoading = true
        error = nil
        defer { if generation == currentGeneration { isLoading = false } }
        do {
            let accountID = selection.accountID
            let repository = selection.repository.lowercased()
            let cached = try context.fetch(FetchDescriptor<JobRunEntity>(predicate: #Predicate {
                $0.accountGitHubUserID == accountID && $0.repositoryFullName == repository
            }))
            let completed = Set(cached.compactMap { entity -> String? in
                guard entity.recordKindRaw == "workflow", entity.statusRaw == "completed", entity.jobDetailsComplete, let attempt = entity.runAttempt else { return nil }
                return "\(entity.githubRunId)/\(attempt)"
            })
            let response = try await loader.page(selection: selection, nextPage: refresh ? nil : nextPage, completedAttempts: completed)
            // Account-wide request budgets outlive the visible selection. Only
            // value metadata is touched here; model access stays behind the guard.
            if response.rateLimit?.remaining == 0 {
                setBackoff(until: response.rateLimit?.resetAt, accountID: selection.accountID, now: now ?? .now)
            }
            guard isCurrent(currentGeneration, selection: selection) else { return }
            for details in response.runs {
                try WorkflowHistoryStore.upsert(run: details.run, jobs: details.jobs ?? [], repository: selection.repository,
                    accountID: selection.accountID, jobsComplete: details.jobs != nil, observedAt: response.observedAt, in: context)
            }
            nextPage = response.nextPage
            rateLimit = response.rateLimit
            if response.rateLimit?.remaining != 0 {
                rateBudget.clearExpired(for: selection.accountID, now: now ?? .now)
            }
            lastRefresh = response.observedAt
            hasLoadedPage = true
            try reloadEntries(in: context)
        } catch {
            if let failure = error as? WorkflowHistoryLoadError, case .rateLimited(let deadline) = failure {
                setBackoff(until: deadline, accountID: selection.accountID, now: now ?? .now)
            }
            guard isCurrent(currentGeneration, selection: selection) else { return }
            self.error = error as? WorkflowHistoryLoadError ?? .unavailable
        }
    }

    private func setBackoff(until deadline: Date?, accountID: Int64, now: Date) {
        rateBudget.recordLimit(until: deadline, accountID: accountID, now: now)
    }

    private func isCurrent(_ generation: Int, selection: WorkflowHistorySelection) -> Bool {
        !Task.isCancelled && self.generation == generation && self.selection == selection
    }

    private func reloadEntries(in context: ModelContext) throws {
        guard let accountID = selection?.accountID else { entries = []; return }
        entries = try context.fetch(FetchDescriptor<JobRunEntity>(predicate: #Predicate { $0.accountGitHubUserID == accountID }))
            .map(WorkflowHistoryEntry.init)
    }
}
