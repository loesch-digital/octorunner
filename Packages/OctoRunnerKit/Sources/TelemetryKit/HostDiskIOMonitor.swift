public actor HostDiskIOMonitor {
    private var previous: HostDiskIOSample?

    public init() {}

    public func currentSnapshot() -> HostDiskIOSnapshot? {
        consume(SystemHostDiskIOSampler().sample())
    }

    public func consume(_ sample: HostDiskIOSample?) -> HostDiskIOSnapshot? {
        defer { previous = sample }
        guard let sample, let previous, sample.uptime.isFinite, previous.uptime.isFinite,
              sample.uptime > previous.uptime else { return nil }
        var reads = 0.0
        var writes = 0.0
        var measured = false
        for (id, current) in sample.devices {
            guard let before = previous.devices[id], current.readBytes >= before.readBytes,
                  current.writtenBytes >= before.writtenBytes else { continue }
            reads += Double(current.readBytes - before.readBytes)
            writes += Double(current.writtenBytes - before.writtenBytes)
            measured = true
        }
        guard measured else { return nil }
        let elapsed = sample.uptime - previous.uptime
        return HostDiskIOSnapshot(readBytesPerSecond: reads / elapsed, writtenBytesPerSecond: writes / elapsed)
    }
}
