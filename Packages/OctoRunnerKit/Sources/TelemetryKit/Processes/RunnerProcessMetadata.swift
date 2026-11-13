import Foundation

public struct RunnerProcessMetadata: Sendable, Equatable {
    public let identity: ProcessIdentity
    public let parentPID: Int32
    public let userID: UInt32
    public let executablePath: String
    public let cpuTimeSeconds: Double?
    public let residentBytes: UInt64?

    public init(identity: ProcessIdentity, parentPID: Int32, userID: UInt32, executablePath: String, cpuTimeSeconds: Double?, residentBytes: UInt64?) {
        self.identity = identity; self.parentPID = parentPID; self.userID = userID
        self.executablePath = executablePath; self.cpuTimeSeconds = cpuTimeSeconds; self.residentBytes = residentBytes
    }

    public func hasSameIdentityAndLocation(as other: Self) -> Bool {
        identity == other.identity && parentPID == other.parentPID && userID == other.userID && executablePath == other.executablePath
    }
}
