import Darwin
import Foundation

public actor RunnerProcessMonitor {
    private let backend: any RunnerProcessBackend
    private let userID: UInt32
    private var previous: RunnerProcessSample?

    public init(backend: any RunnerProcessBackend = SystemRunnerProcessBackend(), userID: UInt32 = geteuid()) {
        self.backend = backend; self.userID = userID
    }

    public func snapshot(targets: [RunnerProcessTarget]) throws -> [InspectedRunnerProcess] {
        try Task.checkCancellation()
        let sample: RunnerProcessSample
        do { sample = try backend.sample() }
        catch { previous = nil; throw error }
        try Task.checkCancellation()
        let attributed = try RunnerProcessTree.associate(sample, targets: targets, userID: userID)
        let old = previous
        previous = sample
        let grouped = Dictionary(grouping: old?.processes ?? [], by: \.identity)
        return attributed.map { process, runner in
            var cpu: Double?
            if let old, sample.uptime.isFinite, old.uptime.isFinite, sample.uptime > old.uptime,
               let entries = grouped[process.identity], entries.count == 1, let prior = entries.first,
               prior.hasSameIdentityAndLocation(as: process),
               let start = prior.cpuTimeSeconds, let end = process.cpuTimeSeconds,
               start.isFinite, end.isFinite, start >= 0, end >= start {
                let value = (end - start) / (sample.uptime - old.uptime) * 100
                if value.isFinite { cpu = value }
            }
            return InspectedRunnerProcess(runner: runner, metadata: process, cpuPercent: cpu, sampledAt: sample.sampledAt)
        }
    }

    public func requestTermination(of selected: InspectedRunnerProcess, targets: [RunnerProcessTarget]) throws {
        try Task.checkCancellation()
        let sample = try backend.sample()
        try Task.checkCancellation()
        let attributed = try RunnerProcessTree.associate(sample, targets: targets, userID: userID)
        guard let fresh = attributed.first(where: { $0.0.identity == selected.id }), fresh.1 == selected.runner,
              fresh.0.hasSameIdentityAndLocation(as: selected.metadata) else { throw RunnerProcessError.changedOrUnattributed }
        try Task.checkCancellation()
        try backend.requestTermination(of: fresh.0)
    }
}
