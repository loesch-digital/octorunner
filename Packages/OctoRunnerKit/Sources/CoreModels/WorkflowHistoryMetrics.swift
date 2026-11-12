import Foundation

/// Metrics describe the loaded history window, never all of GitHub's history.
/// Cancelled/skipped/neutral/unknown conclusions are excluded from success rate.
public struct WorkflowHistoryMetrics: Sendable {
    public let runningCount: Int
    public let queuedCount: Int
    public let completedToday: Int
    public let resolvedRunCount: Int
    public let durationSampleCount: Int
    public let successRate: Double?
    public let averageDurationSeconds: Double?
    public let durationSLARate: Double?

    static let failureConclusions: Set<String> = ["failure", "timed_out", "startup_failure", "action_required", "stale"]

    public init(entries: [WorkflowHistoryEntry], now: Date = .now, calendar: Calendar = .current, durationSLASeconds: Double? = nil) {
        let runs = WorkflowHistoryFilter.latestWorkflows(in: entries)
        runningCount = runs.count { $0.status == "in_progress" }
        queuedCount = runs.count { WorkflowHistoryStatusFilter.queued.matches($0) }
        completedToday = runs.count {
            $0.status == "completed" && $0.completedAt.map { $0 <= now && calendar.isDate($0, inSameDayAs: now) } == true
        }
        let resolved = runs.filter { $0.status == "completed" && ($0.conclusion == "success" || Self.failureConclusions.contains($0.conclusion ?? "")) }
        resolvedRunCount = resolved.count
        successRate = resolved.isEmpty ? nil : Double(resolved.count { $0.conclusion == "success" }) / Double(resolved.count)
        let durations = runs.filter { $0.status == "completed" }.compactMap(\.durationSeconds).filter { $0.isFinite && $0 >= 0 }
        durationSampleCount = durations.count
        averageDurationSeconds = durations.isEmpty ? nil : durations.reduce(0, +) / Double(durations.count)
        if let durationSLASeconds, durationSLASeconds.isFinite, durationSLASeconds > 0, !durations.isEmpty {
            durationSLARate = Double(durations.count { $0 <= durationSLASeconds }) / Double(durations.count)
        } else { durationSLARate = nil }
    }
}
