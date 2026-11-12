import Foundation

public struct WorkflowHistoryFilter: Sendable {
    public var status: WorkflowHistoryStatusFilter
    public var accountID: Int64?
    public var repository: String?
    public var runnerID: Int64?
    public var search: String

    public init(status: WorkflowHistoryStatusFilter = .all, accountID: Int64? = nil, repository: String? = nil, runnerID: Int64? = nil, search: String = "") {
        self.status = status
        self.accountID = accountID
        self.repository = repository
        self.runnerID = runnerID
        self.search = search
    }

    public func apply(to entries: [WorkflowHistoryEntry]) -> [WorkflowHistoryEntry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return Self.latestWorkflows(in: entries).filter { entry in
            guard status.matches(entry), accountID == nil || entry.accountID == accountID else { return false }
            if let repository, entry.repository.caseInsensitiveCompare(repository) != .orderedSame { return false }
            if let runnerID {
                let assigned = entry.runnerID == runnerID || entries.contains {
                    $0.recordKind == "job" && $0.runKey == entry.runKey && $0.attempt == entry.attempt && $0.runnerID == runnerID
                }
                guard assigned else { return false }
            }
            return query.isEmpty || [entry.workflowName, entry.repository, entry.branch, entry.commitSHA, String(entry.githubRunID)]
                .contains { $0.localizedStandardContains(query) }
        }.sorted {
            let left = $0.createdAt ?? $0.startedAt ?? $0.completedAt ?? .distantPast
            let right = $1.createdAt ?? $1.startedAt ?? $1.completedAt ?? .distantPast
            if left != right { return left > right }
            if $0.githubRunID != $1.githubRunID { return $0.githubRunID > $1.githubRunID }
            return $0.id.uuidString < $1.id.uuidString
        }
    }

    static func latestWorkflows(in entries: [WorkflowHistoryEntry]) -> [WorkflowHistoryEntry] {
        var latest: [String: WorkflowHistoryEntry] = [:]
        for entry in entries where entry.recordKind == "workflow" {
            if let old = latest[entry.runKey], (old.attempt ?? 0) > (entry.attempt ?? 0) { continue }
            latest[entry.runKey] = entry
        }
        return Array(latest.values)
    }
}
