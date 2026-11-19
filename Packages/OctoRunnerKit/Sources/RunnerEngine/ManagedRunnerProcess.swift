import CoreModels
import Darwin
import Foundation

/// Owns only processes spawned here. It never adopts a PID from a model or scan.
public actor ManagedRunnerProcess: RunnerProcessControlling {
    private let managedRoot: URL
    private let stopTimeout: Duration
    private var processes: [UUID: RunnerProcessOperation] = [:]

    public init(managedRoot: URL? = nil) {
        self.init(managedRoot: managedRoot, stopTimeout: .seconds(5))
    }

    init(managedRoot: URL?, stopTimeout: Duration) {
        self.managedRoot = managedRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "io.octorunner.macos/runners")
        self.stopTimeout = stopTimeout
    }

    deinit { for process in processes.values { process.signal(force: true) } }

    public func start(configuration: ManagedRunnerConfiguration, generation: UUID) async throws -> RunnerProcessHandle {
        try Task.checkCancellation()
        let base = managedRoot.resolvingSymlinksInPath().standardizedFileURL.path
        let root = configuration.rootDirectory.resolvingSymlinksInPath().standardizedFileURL
        guard configuration.mode == .direct, root.path.hasPrefix(base + "/"),
              root.path == configuration.rootDirectory.standardizedFileURL.path,
              !processes.values.contains(where: {
                  !$0.hasExited && ($0.handle.runnerID == configuration.runnerID || $0.rootPath == root.path)
              }) else {
            throw RunnerSupervisionError.notManaged
        }
        let script = root.appending(path: "run.sh")
        let values = try script.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw RunnerSupervisionError.invalidConfiguration }
        processes = processes.filter { !$0.value.canDiscard }
        let process = try RunnerProcessOperation.spawn(configuration: configuration, generation: generation)
        processes[generation] = process
        // Once the child exists, transfer its handle even if startup has been
        // cancelled. The supervisor retains ownership through any cleanup error.
        return process.handle
    }

    public func stop(_ handle: RunnerProcessHandle, force: Bool) async throws -> RunnerProcessExit {
        guard let process = processes[handle.generation], process.handle == handle else { throw RunnerSupervisionError.notManaged }
        process.signal(force: force)
        let exit = try await process.waitForExit(timeout: stopTimeout)
        processes[handle.generation] = nil
        return exit
    }

    public func exits(for handle: RunnerProcessHandle) -> AsyncStream<RunnerProcessExit> {
        guard let process = processes[handle.generation], process.handle == handle else { return AsyncStream { $0.finish() } }
        return process.subscribe()
    }

    public func activity(for handle: RunnerProcessHandle, listenerPID: Int32?, workerPID: Int32?) -> RunnerActivity {
        guard let process = processes[handle.generation], process.handle == handle else { return .unknown }
        return process.activity(listenerPID: listenerPID, workerPID: workerPID)
    }
}
