import Foundation

public struct WorkflowJobStep: Codable, Sendable, Equatable, Identifiable {
    public let number: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let startedAt: Date?
    public let completedAt: Date?
    public var id: Int { number }
    public var durationSeconds: Double? {
        guard status == "completed", let startedAt, let completedAt else { return nil }
        let seconds = completedAt.timeIntervalSince(startedAt)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }

    public func elapsedDuration(at now: Date?) -> Double? {
        if let durationSeconds { return durationSeconds }
        guard status == "in_progress", let now else { return nil }
        return WorkflowExecutionDuration.elapsedSeconds(since: startedAt, at: now)
    }

    public init(number: Int, name: String, status: String, conclusion: String?, startedAt: Date?, completedAt: Date?) {
        self.number = number; self.name = name; self.status = status
        self.conclusion = conclusion; self.startedAt = startedAt; self.completedAt = completedAt
    }
}
