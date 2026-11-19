public enum RunnerSupervisionError: Error, Equatable, Sendable {
    case notManaged
    case runnerBusy
    case activityUnknown
    case operationInProgress
    case invalidConfiguration
}
