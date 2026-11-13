import Foundation

public enum AppNotificationKind: Sendable, Equatable {
    case runnerOffline
    case runnerOnline
    case runnerError
    case jobFailure
    case lowDiskSpace
}
