import Foundation

/// Reads volume metadata only. Never enumerates the home directory or runner folders.
public actor SystemVolumeCapacitySampler: VolumeCapacitySampling {
    public init() {}

    public func sample() -> VolumeCapacitySnapshot? {
        // A fresh URL avoids reusing URL resource-value caches between samples.
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        guard let values = try? home.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey
        ]), let available = values.volumeAvailableCapacityForImportantUsage,
           let total = values.volumeTotalCapacity else { return nil }
        return VolumeCapacitySnapshot(availableBytes: available, totalBytes: Int64(total))
    }
}
