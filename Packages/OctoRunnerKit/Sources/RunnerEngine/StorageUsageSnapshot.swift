import Foundation

public struct StorageUsageSnapshot: Sendable {
    public let logicalBytesByCategory: [String: Int64]
    public let candidates: [StorageCleanupCandidate]
    public let observedAt: Date
}
