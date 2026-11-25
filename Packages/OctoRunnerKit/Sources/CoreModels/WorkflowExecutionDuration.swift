import Foundation

public enum WorkflowExecutionDuration {
    public static func elapsedSeconds(since start: Date?, at now: Date) -> Double? {
        guard let start else { return nil }
        let seconds = now.timeIntervalSince(start)
        return seconds.isFinite && seconds >= 0 ? seconds : nil
    }
}
