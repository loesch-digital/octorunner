public enum RunnerProcessError: Error, Sendable {
    case unavailable
    case changedOrUnattributed
    case signalFailed(Int32)
}
