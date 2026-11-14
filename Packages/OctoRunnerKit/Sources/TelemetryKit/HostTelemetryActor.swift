import Foundation

public actor HostTelemetryActor {
    private let sampler: any HostTelemetrySampling
    private var previousTicks: HostCPUTicks?

    public init(sampler: any HostTelemetrySampling = SystemHostTelemetrySampler()) {
        self.sampler = sampler
    }

    public func currentSnapshot() -> HostTelemetrySnapshot {
        let sample = sampler.sample()
        let usage = Self.cpuUsage(previous: previousTicks, current: sample.cpuTicks)
        previousTicks = sample.cpuTicks
        let memory = sample.vmStatistics.flatMap { HostMemorySnapshot(statistics: $0, physicalMemoryBytes: sample.physicalMemoryBytes) }
        return HostTelemetrySnapshot(cpuSummary: sample.cpuSummary, totalCoreCount: sample.totalCoreCount,
            physicalMemoryGB: Double(sample.physicalMemoryBytes) / 1_073_741_824,
            usedMemoryGB: memory.map { Double($0.usedBytes) / 1_073_741_824 }, osVersionString: sample.osVersionString,
            cpuUsagePercent: usage, memory: memory,
            performanceCoreCount: sample.performanceCoreCount, efficiencyCoreCount: sample.efficiencyCoreCount,
            coreClusters: sample.coreClusters, memoryPressure: sample.memoryPressure, thermalState: sample.thermalState)
    }

    private static func cpuUsage(previous: HostCPUTicks?, current: HostCPUTicks?) -> Double? {
        guard let previous, let current else { return nil }
        let before = [previous.user, previous.system, previous.idle, previous.nice]
        let after = [current.user, current.system, current.idle, current.nice]
        guard zip(before, after).allSatisfy({ $0 <= $1 }) else { return nil }
        let deltas = zip(before, after).map { Double($1 - $0) }
        let total = deltas.reduce(0, +)
        guard total > 0 else { return nil }
        return (deltas[0] + deltas[1] + deltas[3]) / total * 100
    }
}
