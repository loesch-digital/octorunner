public protocol RunnerProcessBackend: Sendable {
    /// Synchronous system calls run on RunnerProcessMonitor's executor, never the UI actor.
    func sample() throws -> RunnerProcessSample
    /// Recheck the identity immediately before requesting SIGTERM.
    func requestTermination(of process: RunnerProcessMetadata) throws
}
