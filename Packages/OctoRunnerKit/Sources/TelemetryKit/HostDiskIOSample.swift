public struct HostDiskIOSample: Sendable, Equatable {
    public let devices: [UInt64: HostDiskIOCounters]
    public let uptime: Double

    public init(devices: [UInt64: HostDiskIOCounters], uptime: Double) {
        self.devices = devices
        self.uptime = uptime
    }
}
