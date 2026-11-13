public struct WorkflowHistoryRepositoryFailure: Sendable, Equatable {
    public let repository: String
    public let error: WorkflowHistoryLoadError
}
