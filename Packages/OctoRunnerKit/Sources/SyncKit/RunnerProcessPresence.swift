import Foundation

public struct RunnerProcessPresence: Sendable, Equatable {
    public var listenerPID: Int32?
    public var workerPID: Int32?
    public var isWorkerActive: Bool { workerPID != nil }

    public init(listenerPID: Int32? = nil, workerPID: Int32? = nil) {
        self.listenerPID = listenerPID
        self.workerPID = workerPID
    }
}
