import Foundation

public protocol RunnerProcessControlling: Sendable {
    func start(configuration: ManagedRunnerConfiguration, generation: UUID) async throws -> RunnerProcessHandle
    func stop(_ handle: RunnerProcessHandle, force: Bool) async throws -> RunnerProcessExit
    /// One buffered terminal event per generation; not a lossy global log stream.
    func exits(for handle: RunnerProcessHandle) async -> AsyncStream<RunnerProcessExit>
    func activity(for handle: RunnerProcessHandle, listenerPID: Int32?, workerPID: Int32?) async -> RunnerActivity
}
