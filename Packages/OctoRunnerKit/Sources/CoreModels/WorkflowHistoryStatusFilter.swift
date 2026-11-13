public enum WorkflowHistoryStatusFilter: String, CaseIterable, Sendable {
    case all, running, queued, succeeded, failed, cancelled

    func matches(_ entry: WorkflowHistoryEntry) -> Bool {
        switch self {
        case .all: true
        case .running: entry.status == "in_progress"
        case .queued: ["queued", "waiting", "pending", "requested"].contains(entry.status)
        case .succeeded: entry.status == "completed" && entry.conclusion == "success"
        case .failed: entry.status == "completed" && WorkflowHistoryMetrics.failureConclusions.contains(entry.conclusion ?? "")
        case .cancelled: entry.status == "completed" && entry.conclusion == "cancelled"
        }
    }
}
