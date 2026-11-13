public struct HostDiskIOCounters: Sendable, Equatable {
    public let readBytes: UInt64
    public let writtenBytes: UInt64

    public init(readBytes: UInt64, writtenBytes: UInt64) {
        self.readBytes = readBytes
        self.writtenBytes = writtenBytes
    }
}
