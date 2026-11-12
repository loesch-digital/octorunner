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

    private let loader: any WorkflowHistoryLoading
    private var selection: WorkflowHistorySelection?
    private var generation = 0
    private var hasLoadedPage = false
    private var retryDeadlines: [Int64: Date] = [:]
    private var rateFailures: [Int64: Int] = [:]

    public var retryNotBefore: Date? {
        selection.flatMap { retryDeadlines[$0.accountID] }
    }

    public init(loader: any WorkflowHistoryLoading = GitHubWorkflowHistoryLoader()) { self.loader = loader }

    public func select(_ selection: WorkflowHistorySelection?, in context: ModelContext) throws {
        invalidate()
        self.selection = selection
        nextPage = nil
        rateLimit = nil
        error = nil
        lastRefresh = nil
        hasLoadedPage = false
        entries = []
        try reloadEntries(in: context)
    }

    public func invalidate() {
        generation += 1
        isLoading = false
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
            if response.rateLimit?.remaining != 0 && (retryDeadlines[selection.accountID] ?? .distantPast) <= (now ?? .now) {
                retryDeadlines.removeValue(forKey: selection.accountID)
                rateFailures.removeValue(forKey: selection.accountID)
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
        let failures = min((rateFailures[accountID] ?? 0) + 1, 7)
        rateFailures[accountID] = failures
        let fallback = now.addingTimeInterval(min(3_600, 60 * pow(2, Double(failures - 1))))
        let proposed = deadline.flatMap { $0 > now ? $0 : nil } ?? fallback
        retryDeadlines[accountID] = max(retryDeadlines[accountID] ?? .distantPast, proposed)
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
