import CoreModels
import Foundation

/// Job outcomes never change runner availability. Only exact, unambiguous local
/// identities within the active account can contribute to this presentation.
public struct LocalJobResults: Sendable {
    public let latestByRunner: [UUID: WorkflowHistoryEntry]
    public let unreviewedFailures: [WorkflowHistoryEntry]

    public init() { latestByRunner = [:]; unreviewedFailures = [] }

    @MainActor
    public init(entries: [WorkflowHistoryEntry], runners: [RunnerEntity], accountID: Int64?,
                reviewed: Set<String>, now: Date = .now) {
        guard let accountID, accountID > 0 else {
            latestByRunner = [:]; unreviewedFailures = []; return
        }
        let entries = entries.filter { $0.accountID == accountID }
        var attempts: [String: Int] = [:]
        for entry in entries {
            if let attempt = entry.attempt {
                let key = "\(entry.repository.lowercased())|\(entry.githubRunID)"
                attempts[key] = max(attempts[key] ?? 0, attempt)
            }
        }
        var latest: [UUID: WorkflowHistoryEntry] = [:]
        var failures: [WorkflowHistoryEntry] = []
        var included: Set<String> = []
        let runnersByID = Dictionary(grouping: runners.filter { ($0.githubRunnerId ?? 0) > 0 }, by: { $0.githubRunnerId! })
        for entry in entries.sorted(by: Self.newerFirst) {
            guard entry.recordKind == "job", entry.status == "completed",
                  (entry.githubJobID ?? 0) > 0, entry.githubRunID > 0,
                  let attempt = entry.attempt, attempt > 0,
                  let completed = entry.completedAt, completed <= now,
                  let observed = entry.observedAt, completed <= observed.addingTimeInterval(5),
                  observed <= now.addingTimeInterval(5) else { continue }
            let matches = (runnersByID[entry.runnerID ?? 0] ?? []).filter { Self.matches($0, entry: entry) }
            guard matches.count == 1, let runner = matches.first else { continue }
            let key = Self.reviewKey(entry)
            guard included.insert(key).inserted else { continue }
            if latest[runner.id] == nil { latest[runner.id] = entry }
            if Self.isFailure(entry), !reviewed.contains(key),
               attempts["\(entry.repository.lowercased())|\(entry.githubRunID)"] == attempt { failures.append(entry) }
        }
        latestByRunner = latest
        unreviewedFailures = failures
    }

    public static func reviewKey(_ entry: WorkflowHistoryEntry) -> String {
        "\(entry.accountID ?? 0)|\(entry.repository.lowercased())|\(entry.githubRunID)|\(entry.attempt ?? 0)|\(entry.githubJobID ?? 0)"
    }

    public static func isFailure(_ entry: WorkflowHistoryEntry) -> Bool {
        entry.status == "completed" && ["failure", "timed_out", "startup_failure", "action_required", "stale"].contains(entry.conclusion ?? "")
    }

    private static func newerFirst(_ left: WorkflowHistoryEntry, _ right: WorkflowHistoryEntry) -> Bool {
        if left.completedAt != right.completedAt { return (left.completedAt ?? .distantPast) > (right.completedAt ?? .distantPast) }
        if left.githubJobID != right.githubJobID { return (left.githubJobID ?? 0) > (right.githubJobID ?? 0) }
        return left.id.uuidString < right.id.uuidString
    }

    @MainActor
    private static func matches(_ runner: RunnerEntity, entry: WorkflowHistoryEntry) -> Bool {
        guard let id = runner.githubRunnerId, id > 0, entry.runnerID == id else { return false }
        switch runner.scopeType {
        case .repository: return GitHubRepositorySlug(input: runner.scopeUrlString)?.rawValue == entry.repository.lowercased()
        case .organization:
            guard let url = URLComponents(string: runner.scopeUrlString), url.scheme == "https", url.host?.lowercased() == "github.com",
                  url.port == nil || url.port == 443, url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
                  !url.percentEncodedPath.contains("%") else { return false }
            let parts = url.path.split(separator: "/")
            guard parts.count == 1, let owner = parts.first,
                  url.percentEncodedPath == "/\(owner)" || url.percentEncodedPath == "/\(owner)/" else { return false }
            return owner.lowercased() == entry.repository.split(separator: "/").first?.lowercased()
        case .personalMultiRepo: return false
        }
    }
}
