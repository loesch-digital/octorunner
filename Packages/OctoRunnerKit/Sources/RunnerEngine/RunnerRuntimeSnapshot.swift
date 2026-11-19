import CoreModels
import Foundation

public enum RunnerRuntimePhase: String, Sendable {
    case stopped, starting, running, draining, drainTimedOut, stopping, faulted
    case waitingToRestart, waitingForPower, waitingForCapacity, quarantined
}
public enum RunnerActivity: String, Sendable { case unknown, idle, busy }

public struct RunnerRuntimeSnapshot: Sendable, Equatable {
    public let runnerID: UUID
    public let mode: RunnerExecutionMode
    public let generation: UUID?
    public let pid: Int32?
    public let startedAt: Date?
    public let phase: RunnerRuntimePhase
    public let activity: RunnerActivity
    public let lastExitStatus: Int32?
}

public struct RunnerProcessObservationTarget: Sendable {
    public let rootPath: String
    let handle: RunnerProcessHandle
}
