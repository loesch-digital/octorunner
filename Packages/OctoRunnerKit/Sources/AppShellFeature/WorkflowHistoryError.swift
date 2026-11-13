public enum WorkflowHistoryError: Error, Equatable, Sendable {
    case inconsistentPayload
    case invalidRepository
}
