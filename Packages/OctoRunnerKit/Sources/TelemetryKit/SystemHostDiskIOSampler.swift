import Foundation
import IOKit
import IOKit.storage

/// Host block-device statistics only; no filesystem traversal or file contents.
public struct SystemHostDiskIOSampler: Sendable {
    public init() {}

    public func sample() -> HostDiskIOSample? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var devices: [UInt64: HostDiskIOCounters] = [:]
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard !Task.isCancelled else { return nil }
            var identity: UInt64 = 0
            guard IORegistryEntryGetRegistryEntryID(service, &identity) == KERN_SUCCESS,
                  let property = IORegistryEntryCreateCFProperty(service, kIOBlockStorageDriverStatisticsKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue(),
                  let values = property as? [String: Any], let counters = Self.counters(from: values) else { continue }
            devices[identity] = counters
        }
        guard !devices.isEmpty else { return nil }
        return HostDiskIOSample(devices: devices, uptime: ProcessInfo.processInfo.systemUptime)
    }

    static func counters(from values: [String: Any]) -> HostDiskIOCounters? {
        guard let read = values[kIOBlockStorageDriverStatisticsBytesReadKey] as? NSNumber,
              let written = values[kIOBlockStorageDriverStatisticsBytesWrittenKey] as? NSNumber,
              let reads = UInt64(read.stringValue), let writes = UInt64(written.stringValue) else { return nil }
        return HostDiskIOCounters(readBytes: reads, writtenBytes: writes)
    }
}
