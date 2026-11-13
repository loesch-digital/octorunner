import Foundation
import GitHubAPI
import Observation

/// Shared for the application lifetime, independent of any history view.
@MainActor
@Observable
public final class WorkflowHistoryRateBudget {
    private var retryDeadlines: [Int64: Date] = [:]
    private var rateFailures: [Int64: Int] = [:]
    private var observations: [Int64: GitHubRateLimitSnapshot] = [:]

    public init() {}
    public func deadline(for accountID: Int64) -> Date? { retryDeadlines[accountID] }
    public func snapshot(for accountID: Int64) -> GitHubRateLimitSnapshot? { observations[accountID] }

    func observe(_ snapshot: GitHubRateLimitSnapshot?, accountID: Int64) {
        guard let snapshot, snapshot.observedAt >= (observations[accountID]?.observedAt ?? .distantPast) else { return }
        observations[accountID] = snapshot
    }

    func recordLimit(until deadline: Date?, accountID: Int64, now: Date) {
        let failures = min((rateFailures[accountID] ?? 0) + 1, 7)
        rateFailures[accountID] = failures
        let fallback = now.addingTimeInterval(min(3_600, 60 * pow(2, Double(failures - 1))))
        let proposed = deadline.flatMap { $0 > now ? $0 : nil } ?? fallback
        retryDeadlines[accountID] = max(retryDeadlines[accountID] ?? .distantPast, proposed)
    }

    func clearExpired(for accountID: Int64, now: Date) {
        guard (retryDeadlines[accountID] ?? .distantPast) <= now else { return }
        retryDeadlines.removeValue(forKey: accountID)
        rateFailures.removeValue(forKey: accountID)
    }
}
