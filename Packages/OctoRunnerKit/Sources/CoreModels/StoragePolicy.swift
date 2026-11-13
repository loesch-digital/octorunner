import Foundation

public struct StoragePolicy: Codable, Sendable, Equatable {
    public var logRetentionDays: Int = 14
    public var pruningMode: WorkspacePruningMode = .manual
    public var minimumFreeSpaceGB: Int = 20

    public init() {}

    public func validated() -> Self {
        var result = self
        result.logRetentionDays = [7, 14, 30, 90].contains(logRetentionDays) ? logRetentionDays : 14
        result.minimumFreeSpaceGB = min(max(minimumFreeSpaceGB, 1), 1_000)
        return result
    }
}
