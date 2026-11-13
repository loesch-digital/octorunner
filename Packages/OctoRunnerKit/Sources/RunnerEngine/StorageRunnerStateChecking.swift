public protocol StorageRunnerStateChecking: Sendable {
    func isStopped(_ runner: ManagedStorageRunner) async throws -> Bool
}
