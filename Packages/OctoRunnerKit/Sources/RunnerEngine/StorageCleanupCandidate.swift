import Foundation

public struct StorageCleanupCandidate: Sendable, Identifiable {
    public let runnerID: UUID
    public let relativePath: String
    public let category: String
    public let logicalBytes: Int64
    public let modifiedAt: Date
    let inode: UInt64
    let device: Int32
    public var id: String { "\(runnerID)|\(relativePath)|\(device)|\(inode)" }
}
