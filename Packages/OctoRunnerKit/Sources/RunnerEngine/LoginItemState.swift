import Foundation

public enum LoginItemState: Sendable, Equatable {
    case enabled
    case requiresApproval
    case disabled
    case unavailable
}
