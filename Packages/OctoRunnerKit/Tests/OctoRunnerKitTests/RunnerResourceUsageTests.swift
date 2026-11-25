import Foundation
import TelemetryKit
import Testing

struct RunnerResourceUsageTests {
    @Test("CPU and RAM are grouped by runner and CPU can exceed one core")
    func groupMeasurements() {
        let first = RunnerProcessTarget(id: UUID(), name: "Build", rootPath: "/runner-one")
        let second = RunnerProcessTarget(id: UUID(), name: "Test", rootPath: "/runner-two")
        let usage = RunnerResourceUsage.byRunner([
            process(first, pid: 21, cpu: 90, bytes: 300),
            process(first, pid: 22, cpu: 74, bytes: 100),
            process(second, pid: 31, cpu: nil, bytes: 5)
        ])
        #expect(usage[first.id]?.cpuPercent == 164)
        #expect(usage[first.id]?.residentBytes == 400)
        #expect(usage[second.id]?.cpuPercent == nil)
        #expect(usage[second.id]?.residentBytes == 5)
    }

    @Test("Missing usage stays unknown and measured zero remains zero")
    func missingUsage() {
        let target = RunnerProcessTarget(id: UUID(), name: "Build", rootPath: "/runner")
        let unknown = RunnerResourceUsage.byRunner([process(target, pid: 21, cpu: nil, bytes: nil)])
        let idle = RunnerResourceUsage.byRunner([process(target, pid: 21, cpu: 0, bytes: nil)])
        #expect(unknown[target.id]?.cpuPercent == nil)
        #expect(unknown[target.id]?.residentBytes == nil)
        #expect(idle[target.id]?.cpuPercent == 0)
        #expect(RunnerResourceUsage.byRunner([]).isEmpty)
    }

    private func process(_ target: RunnerProcessTarget, pid: Int32, cpu: Double?, bytes: UInt64?) -> InspectedRunnerProcess {
        let metadata = RunnerProcessMetadata(
            identity: ProcessIdentity(pid: pid, startSeconds: 100, startMicroseconds: 0),
            parentPID: 1, userID: 501, executablePath: target.rootPath + "/bin/Runner.Listener",
            cpuTimeSeconds: nil, residentBytes: bytes
        )
        return InspectedRunnerProcess(runner: target, metadata: metadata, cpuPercent: cpu, sampledAt: .now)
    }
}
