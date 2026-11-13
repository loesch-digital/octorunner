import Foundation
import Testing
@testable import TelemetryKit

struct HostDiskIOMonitorTests {
    @Test("Device throughput needs a baseline and excludes reset or newly attached devices")
    func rates() async {
        let monitor = HostDiskIOMonitor()
        let first = await monitor.consume(HostDiskIOSample(devices: [1: .init(readBytes: 100, writtenBytes: 200)], uptime: 10))
        #expect(first == nil)
        let second = await monitor.consume(HostDiskIOSample(devices: [1: .init(readBytes: 300, writtenBytes: 600), 2: .init(readBytes: 1_000_000, writtenBytes: 1_000_000)], uptime: 12))
        #expect(second?.readBytesPerSecond == 100)
        #expect(second?.writtenBytesPerSecond == 200)
        let reset = await monitor.consume(HostDiskIOSample(devices: [1: .init(readBytes: 1, writtenBytes: 1)], uptime: 14))
        #expect(reset == nil)
        let recovered = await monitor.consume(HostDiskIOSample(devices: [1: .init(readBytes: 21, writtenBytes: 41)], uptime: 16))
        #expect(recovered?.readBytesPerSecond == 10)
        #expect(recovered?.writtenBytesPerSecond == 20)
    }

    @Test("Missing samples and nonmonotonic timestamps reset the throughput baseline")
    func invalidSamples() async {
        let monitor = HostDiskIOMonitor()
        let sample = HostDiskIOSample(devices: [1: .init(readBytes: 0, writtenBytes: 0)], uptime: 5)
        #expect(await monitor.consume(sample) == nil)
        #expect(await monitor.consume(sample) == nil)
        #expect(await monitor.consume(nil) == nil)
        #expect(await monitor.consume(HostDiskIOSample(devices: [1: .init(readBytes: 999, writtenBytes: 999)], uptime: 10)) == nil)
    }
}
