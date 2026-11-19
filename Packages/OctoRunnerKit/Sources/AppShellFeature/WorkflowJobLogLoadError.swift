enum WorkflowJobLogLoadError: Equatable {
    case authenticationRequired
    case permissionDenied
    case notAvailable
    case rateLimited
    case unsupportedContent
    case unavailable
}
