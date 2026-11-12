import Foundation

public struct NotificationPolicy: Codable, Sendable, Equatable {
    public var enabled: Bool = false
    public var runnerOffline: Bool = true
    public var runnerOnline: Bool = false
    public var runnerError: Bool = false
    public var jobFailure: Bool = true
    public var lowDiskSpace: Bool = true
    public var soundEnabled: Bool = true

    public init() {}

    private enum CodingKeys: String, CodingKey {
        case enabled, runnerOffline, runnerOnline, runnerError, jobFailure, lowDiskSpace, soundEnabled
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try values.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        runnerOffline = try values.decodeIfPresent(Bool.self, forKey: .runnerOffline) ?? true
        runnerOnline = try values.decodeIfPresent(Bool.self, forKey: .runnerOnline) ?? false
        runnerError = try values.decodeIfPresent(Bool.self, forKey: .runnerError) ?? false
        jobFailure = try values.decodeIfPresent(Bool.self, forKey: .jobFailure) ?? true
        lowDiskSpace = try values.decodeIfPresent(Bool.self, forKey: .lowDiskSpace) ?? true
        soundEnabled = try values.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
    }
}
