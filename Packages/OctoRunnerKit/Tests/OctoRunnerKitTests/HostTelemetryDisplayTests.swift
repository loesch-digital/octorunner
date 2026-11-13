import AppShellFeature
import Foundation
import TelemetryKit
import Testing

struct HostTelemetryDisplayTests {
    @Test("Missing telemetry never displays invented hardware or a nominal memory pressure")
    func missingSample() {
        let display = HostTelemetryDisplay(snapshot: nil, locale: Locale(identifier: "en_US"))
        #expect(display.cpuBrand == "—")
        #expect(display.coreCount == "—")
        #expect(display.memoryCapacity == "—")
        #expect(display.memoryUsed == "—")
    }

    @Test("Measured memory and cores are formatted from the snapshot using the selected locale")
    func measuredSample() {
        let snapshot = HostTelemetrySnapshot(cpuSummary: "Fixture CPU", totalCoreCount: 10, physicalMemoryGB: 16, usedMemoryGB: 6.5, osVersionString: "Fixture")
        let display = HostTelemetryDisplay(snapshot: snapshot, locale: Locale(identifier: "de_DE"))
        #expect(display.cpuBrand == "Fixture CPU")
        #expect(display.coreCount == "10")
        #expect(display.memoryCapacity == "16,0")
        #expect(display.memoryUsed == "6,5")
        let unavailable = HostTelemetrySnapshot(cpuSummary: "Fixture CPU", totalCoreCount: 10, physicalMemoryGB: 16, usedMemoryGB: nil, osVersionString: "Fixture")
        #expect(HostTelemetryDisplay(snapshot: unavailable, locale: Locale(identifier: "en_US")).memoryUsed == "—")
    }
}
