import Foundation

public struct RunnerProcessHandle: Sendable, Equatable {
    public let runnerID: UUID
    public let generation: UUID
    public let pid: Int32
    public let startedAt: Date

    public init(runnerID: UUID, generation: UUID, pid: Int32, startedAt: Date) {
        self.runnerID = runnerID; self.generation = generation; self.pid = pid; self.startedAt = startedAt
    }
}
