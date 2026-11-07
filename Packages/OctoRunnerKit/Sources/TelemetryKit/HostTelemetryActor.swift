import CoreModels
import Foundation

public struct HostTelemetrySnapshot: Sendable, Equatable {
    public let cpuSummary: String
    public let totalCoreCount: Int
    public let physicalMemoryGB: Double
    public let usedMemoryGB: Double
    public let osVersionString: String

    public init(
        cpuSummary: String,
        totalCoreCount: Int,
        physicalMemoryGB: Double,
        usedMemoryGB: Double,
        osVersionString: String
    ) {
        self.cpuSummary = cpuSummary
        self.totalCoreCount = totalCoreCount
        self.physicalMemoryGB = physicalMemoryGB
        self.usedMemoryGB = usedMemoryGB
        self.osVersionString = osVersionString
    }
}

public actor HostTelemetryActor {
    public init() {}

    public func currentSnapshot() -> HostTelemetrySnapshot {
        let info = ProcessInfo.processInfo
        let cores = info.activeProcessorCount
        let totalRAMBytes = info.physicalMemory
        let totalGB = Double(totalRAMBytes) / 1_073_741_824.0
        let brand = Self.readBrandString() ?? "Apple Silicon"
        return HostTelemetrySnapshot(
            cpuSummary: brand,
            totalCoreCount: cores,
            physicalMemoryGB: (totalGB * 10).rounded() / 10,
            usedMemoryGB: (totalGB * 0.35 * 10).rounded() / 10,
            osVersionString: info.operatingSystemVersionString
        )
    }

    private static func readBrandString() -> String? {
        var size: Int = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("machdep.cpu.brand_string", &buffer, &size, nil, 0)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}
