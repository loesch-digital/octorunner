import Foundation

public enum WorkflowHistoryLoadError: Error, Equatable, Sendable {
    case authenticationRequired
    case permissionDenied
    case resourceNotFound
    case rateLimited(until: Date?)
    case tooManyPages
    case unavailable
}
