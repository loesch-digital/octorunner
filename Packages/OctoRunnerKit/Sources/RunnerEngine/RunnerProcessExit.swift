public struct RunnerProcessExit: Sendable, Equatable {
    public let handle: RunnerProcessHandle
    /// A normal exit code, or the negative terminating signal.
    public let status: Int32
    public init(handle: RunnerProcessHandle, status: Int32) { self.handle = handle; self.status = status }
}
