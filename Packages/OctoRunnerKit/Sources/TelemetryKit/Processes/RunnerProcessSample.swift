import Foundation

public struct RunnerProcessSample: Sendable {
    public let uptime: Double
    public let sampledAt: Date
    public let processes: [RunnerProcessMetadata]

    public init(uptime: Double, sampledAt: Date, processes: [RunnerProcessMetadata]) {
        self.uptime = uptime; self.sampledAt = sampledAt; self.processes = processes
    }
}
