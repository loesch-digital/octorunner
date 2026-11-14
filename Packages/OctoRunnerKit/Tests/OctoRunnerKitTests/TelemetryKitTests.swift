import Foundation
import TelemetryKit
import Testing
import Synchronization

@Suite("TelemetryKit Apple Silicon Hardware Tests")
struct TelemetryKitTests {
    @Test("HostTelemetryActor reads Apple Silicon CPU and memory metrics")
    func hostTelemetryMetrics() async {
        let actor = HostTelemetryActor()
        let snapshot = await actor.currentSnapshot()
        #expect(snapshot.totalCoreCount > 0)
        #expect(snapshot.physicalMemoryGB >= 4.0)
        #expect((snapshot.usedMemoryGB ?? 0) > 0)
        #expect(!snapshot.cpuSummary.isEmpty)
        #expect(!snapshot.osVersionString.isEmpty)
    }

    @Test("CPU load uses tick deltas and reports the first, missing and reset samples as unknown")
    func cpuDeltas() async {
        let provider = FixtureHostSampler(samples: [
            sample(ticks: HostCPUTicks(user: 100, system: 100, idle: 800, nice: 0)),
            sample(ticks: HostCPUTicks(user: 150, system: 150, idle: 900, nice: 0)),
            sample(ticks: HostCPUTicks(user: 1, system: 1, idle: 1, nice: 0)),
            sample(ticks: nil),
            sample(ticks: HostCPUTicks(user: 2, system: 2, idle: 2, nice: 0)),
            sample(ticks: HostCPUTicks(user: 3, system: 3, idle: 8, nice: 0))
        ])
        let monitor = HostTelemetryActor(sampler: provider)
        #expect(await monitor.currentSnapshot().cpuUsagePercent == nil)
        #expect(await monitor.currentSnapshot().cpuUsagePercent == 50)
        #expect(await monitor.currentSnapshot().cpuUsagePercent == nil)
        #expect(await monitor.currentSnapshot().cpuUsagePercent == nil)
        #expect(await monitor.currentSnapshot().cpuUsagePercent == nil)
        #expect(await monitor.currentSnapshot().cpuUsagePercent == 25)
    }

    @Test("Memory uses anonymous, wired and actual compressed pages without counting reclaimable pages twice")
    func memoryBreakdown() async throws {
        let vm = HostVMStatistics(pageSize: 16_384, anonymousPages: 100, wiredPages: 20, compressedPages: 30, purgeablePages: 10)
        let monitor = HostTelemetryActor(sampler: FixtureHostSampler(samples: [sample(ticks: nil, vm: vm)]))
        let snapshot = await monitor.currentSnapshot()
        let memory = try #require(snapshot.memory)
        #expect(memory.appBytes == 1_474_560)
        #expect(memory.wiredBytes == 327_680)
        #expect(memory.compressedBytes == 491_520)
        #expect(memory.usedBytes == 2_293_760)
        #expect(snapshot.usedMemoryGB == Double(2_293_760) / 1_073_741_824)
        #expect(snapshot.performanceCoreCount == 6)
        #expect(snapshot.efficiencyCoreCount == 4)
    }

    @Test("Missing or inconsistent VM counters never become a fabricated used-memory value")
    func unknownMemory() async {
        for vm in [nil,
                   HostVMStatistics(pageSize: 0, anonymousPages: 1, wiredPages: 1, compressedPages: 1, purgeablePages: 0),
                   HostVMStatistics(pageSize: 16_384, anonymousPages: 1, wiredPages: 1, compressedPages: 1, purgeablePages: 2),
                   HostVMStatistics(pageSize: .max, anonymousPages: .max, wiredPages: 1, compressedPages: 1, purgeablePages: 0)] {
            let monitor = HostTelemetryActor(sampler: FixtureHostSampler(samples: [sample(ticks: nil, vm: vm)]))
            #expect(await monitor.currentSnapshot().usedMemoryGB == nil)
        }
    }

    @Test("Host pressure uses dispatch flags, remains independent of thermals and clears unavailable readings")
    func pressureAndThermals() async {
        // Kernel sysctl exports dispatch flags, not the kernel's internal 0/1/3 levels.
        let cases: [(Int32?, Int?, HostMemoryPressure?, HostThermalState?)] = [
            (1, 3, .normal, .critical), (2, 0, .warning, .nominal),
            (4, 1, .critical, .fair), (nil, 2, nil, .serious),
            (0, nil, nil, nil), (3, 99, nil, nil), (8, -1, nil, nil),
            (-1, nil, nil, nil)
        ]
        let provider = FixtureHostSampler(samples: cases.map { pressure, thermal, _, _ in
            HostTelemetrySample(cpuSummary: "Fixture", totalCoreCount: 4,
                physicalMemoryBytes: 8_589_934_592, osVersionString: "Fixture", cpuTicks: nil, vmStatistics: nil,
                memoryPressure: pressure.flatMap(HostMemoryPressure.init(rawValue:)),
                thermalState: thermal.flatMap(HostThermalState.init(rawValue:)))
        })
        let monitor = HostTelemetryActor(sampler: provider)
        for (_, _, pressure, thermal) in cases {
            let snapshot = await monitor.currentSnapshot()
            #expect(snapshot.memoryPressure == pressure)
            #expect(snapshot.thermalState == thermal)
        }
    }

    private func sample(ticks: HostCPUTicks?, vm: HostVMStatistics? = nil) -> HostTelemetrySample {
        HostTelemetrySample(cpuSummary: "Fixture CPU", totalCoreCount: 10, physicalMemoryBytes: 16 * 1_073_741_824, osVersionString: "Fixture OS", cpuTicks: ticks, vmStatistics: vm, performanceCoreCount: 6, efficiencyCoreCount: 4)
    }

    @Test("CPU topology preserves reported cluster names instead of assuming every host has efficiency cores")
    func namedClusters() async {
        let input = HostTelemetrySample(cpuSummary: "Fixture CPU", totalCoreCount: 15,
            physicalMemoryBytes: 16 * 1_073_741_824, osVersionString: "Fixture OS", cpuTicks: nil, vmStatistics: nil,
            coreClusters: [HostCPUCluster(id: 0, name: "Super", physicalCoreCount: 5),
                           HostCPUCluster(id: 1, name: "Performance", physicalCoreCount: 10)])
        let monitor = HostTelemetryActor(sampler: FixtureHostSampler(samples: [input]))
        let snapshot = await monitor.currentSnapshot()
        #expect(snapshot.coreClusters.map(\.name) == ["Super", "Performance"])
        #expect(snapshot.coreClusters.map(\.physicalCoreCount) == [5, 10])
        #expect(snapshot.efficiencyCoreCount == nil)
    }
}

private final class FixtureHostSampler: HostTelemetrySampling, Sendable {
    private let samples: Synchronization.Mutex<[HostTelemetrySample]>
    init(samples: [HostTelemetrySample]) { self.samples = Synchronization.Mutex(samples) }
    func sample() -> HostTelemetrySample { samples.withLock { $0.removeFirst() } }
}
