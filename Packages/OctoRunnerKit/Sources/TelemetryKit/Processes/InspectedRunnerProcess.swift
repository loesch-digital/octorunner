import Foundation

public struct InspectedRunnerProcess: Sendable, Identifiable {
    public let runner: RunnerProcessTarget
    public let metadata: RunnerProcessMetadata
    public let cpuPercent: Double?
    public let sampledAt: Date
    public var id: ProcessIdentity { metadata.identity }
    public var name: String { URL(fileURLWithPath: metadata.executablePath).lastPathComponent }
    public var runtimeSeconds: Double { max(0, sampledAt.timeIntervalSince(metadata.identity.startedAt)) }

    public init(runner: RunnerProcessTarget, metadata: RunnerProcessMetadata, cpuPercent: Double?, sampledAt: Date) {
        self.runner = runner; self.metadata = metadata; self.cpuPercent = cpuPercent; self.sampledAt = sampledAt
    }
}
