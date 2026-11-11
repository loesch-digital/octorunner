import Foundation

public enum AppNotificationKind: Sendable, Equatable {
    case runnerOffline
    case jobFailure
    case lowDiskSpace
}
