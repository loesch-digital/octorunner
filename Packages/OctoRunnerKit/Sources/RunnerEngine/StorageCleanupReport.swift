public struct StorageCleanupReport: Sendable {
    public let removedCount: Int
    public let removedLogicalBytes: Int64
    public let skippedCount: Int
}
