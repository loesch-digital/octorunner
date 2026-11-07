import Foundation
import TelemetryKit
import Testing

@Suite("TelemetryKit Apple Silicon Hardware Tests")
struct TelemetryKitTests {
    @Test("HostTelemetryActor reads Apple Silicon CPU and memory metrics")
    func hostTelemetryMetrics() async {
        let actor = HostTelemetryActor()
        let snapshot = await actor.currentSnapshot()
        #expect(snapshot.totalCoreCount > 0)
        #expect(snapshot.physicalMemoryGB >= 4.0)
        #expect(snapshot.usedMemoryGB > 0)
        #expect(!snapshot.cpuSummary.isEmpty)
        #expect(!snapshot.osVersionString.isEmpty)
    }
}
