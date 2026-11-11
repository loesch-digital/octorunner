import Foundation

public struct NotificationPolicy: Codable, Sendable, Equatable {
    public var enabled: Bool = false
    public var runnerOffline: Bool = true
    public var jobFailure: Bool = true
    public var lowDiskSpace: Bool = true
    public var soundEnabled: Bool = true

    public init() {}
}
