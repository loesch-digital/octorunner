import Foundation

/// Local runner management policy. Workflow step shells remain defined by GitHub workflows.
public struct RunnerRuntimePolicy: Codable, Sendable, Equatable {
    public var shell: RunnerShell = .bash
    public var restartPolicy: RunnerRestartPolicy = .always
    public var restartDelaySeconds: Int = 10
    public var quarantineThreshold: Int = 5
    public var gracefulDrainEnabled: Bool = true
    public var drainTimeoutSeconds: Int = 300
    public var batterySaverEnabled: Bool = false

    public init() {}

    public func validated() -> Self {
        var result = self
        result.restartDelaySeconds = min(max(restartDelaySeconds, 1), 300)
        result.quarantineThreshold = min(max(quarantineThreshold, 1), 100)
        result.drainTimeoutSeconds = min(max(drainTimeoutSeconds, 1), 3_600)
        return result
    }
}
