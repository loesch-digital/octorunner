import Foundation

/// PID alone is insufficient: the kernel may assign it to a new process.
public struct ProcessIdentity: Hashable, Sendable {
    public let pid: Int32
    public let startSeconds: UInt64
    public let startMicroseconds: UInt64

    public init(pid: Int32, startSeconds: UInt64, startMicroseconds: UInt64) {
        self.pid = pid; self.startSeconds = startSeconds; self.startMicroseconds = startMicroseconds
    }

    public var startedAt: Date { Date(timeIntervalSince1970: Double(startSeconds) + Double(startMicroseconds) / 1_000_000) }
}
