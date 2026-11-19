import Darwin
import Foundation
import Synchronization

/// Reaping and signalling share a lock: a child PID cannot be recycled between
/// our identity check and a signal. No unrelated process is ever adopted.
final class RunnerProcessOperation: Sendable {
    private struct ExitWaiter {
        let continuation: CheckedContinuation<RunnerProcessExit, any Error>
        let timer: Task<Void, Never>
    }

    private struct State {
        var exit: RunnerProcessExit?
        var waiters: [UUID: ExitWaiter] = [:]
        var source: (any DispatchSourceProcess)?
        var groupTimer: (any DispatchSourceTimer)?
        var subscribed = false
    }
    let handle: RunnerProcessHandle
    let rootPath: String
    private let outputReaders: [RunnerProcessLogPipe.Reader]
    private let state = Mutex(State())
    private let terminal = AsyncStream<RunnerProcessExit>.makeStream(bufferingPolicy: .bufferingNewest(1))
    var hasExited: Bool { state.withLock { $0.exit != nil } }
    var canDiscard: Bool { state.withLock { $0.exit != nil && $0.subscribed } }

    private init(handle: RunnerProcessHandle, rootDirectory: URL, outputReaders: [RunnerProcessLogPipe.Reader]) {
        self.handle = handle
        self.rootPath = rootDirectory.standardizedFileURL.path
        self.outputReaders = outputReaders
    }

    static func spawn(configuration: ManagedRunnerConfiguration, generation: UUID, console: RunnerProcessConsole) throws -> RunnerProcessOperation {
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        try check(posix_spawn_file_actions_init(&actions))
        defer { posix_spawn_file_actions_destroy(&actions) }
        try check(posix_spawnattr_init(&attributes))
        defer { posix_spawnattr_destroy(&attributes) }
        try check(posix_spawnattr_setpgroup(&attributes, 0))
        var mask = sigset_t(); sigemptyset(&mask)
        var defaults = sigset_t(); sigemptyset(&defaults)
        for signal in [SIGINT, SIGTERM, SIGQUIT, SIGHUP, SIGPIPE] { sigaddset(&defaults, signal) }
        try check(posix_spawnattr_setsigmask(&attributes, &mask))
        try check(posix_spawnattr_setsigdefault(&attributes, &defaults))
        try check(posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF)))
        try check(posix_spawn_file_actions_addchdir_np(&actions, configuration.rootDirectory.path))
        try check(posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0))
        let stdout = try RunnerProcessLogPipe(console: console, standardError: false)
        let stderr = try RunnerProcessLogPipe(console: console, standardError: true)
        try check(posix_spawn_file_actions_adddup2(&actions, stdout.writer.fd, STDOUT_FILENO))
        try check(posix_spawn_file_actions_adddup2(&actions, stderr.writer.fd, STDERR_FILENO))
        let environment = ProcessInfo.processInfo.environment.merging(configuration.launch.environment) { _, configured in configured }
        let arguments = ["/bin/bash", configuration.rootDirectory.appending(path: "run.sh").path]
        let argv = arguments.map { strdup($0) } + [nil]
        let envp = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { argv.forEach { free($0) }; envp.forEach { free($0) } }
        guard argv.dropLast().allSatisfy({ $0 != nil }), envp.dropLast().allSatisfy({ $0 != nil }) else { throw POSIXError(.ENOMEM) }
        var pid: pid_t = 0
        let result = withExtendedLifetime((stdout.writer, stderr.writer)) {
            argv.withUnsafeBufferPointer { args in
                envp.withUnsafeBufferPointer { env in
                    posix_spawn(&pid, "/bin/bash", &actions, &attributes,
                        UnsafeMutablePointer(mutating: args.baseAddress!), UnsafeMutablePointer(mutating: env.baseAddress!))
                }
            }
        }
        try check(result)
        let operation = RunnerProcessOperation(handle: .init(runnerID: configuration.runnerID,
            generation: generation, pid: pid, startedAt: .now), rootDirectory: configuration.rootDirectory,
            outputReaders: [stdout.reader, stderr.reader])
        operation.beginMonitoring()
        return operation
    }

    func subscribe() -> AsyncStream<RunnerProcessExit> {
        state.withLock { $0.subscribed = true }
        return terminal.stream
    }

    func signal(force: Bool) {
        state.withLock { state in
            guard state.exit == nil else { return }
            // The unreaped child reserves the group leader PID until reap().
            // POSIX_SPAWN_SETPGROUP assigned this fresh group atomically at spawn.
            _ = kill(-handle.pid, force ? SIGKILL : SIGTERM)
        }
    }

    func activity(listenerPID: Int32?, workerPID: Int32?) -> RunnerActivity {
        state.withLock { state in
            guard state.exit == nil else { return .unknown }
            if let workerPID {
                return belongsToGroup(workerPID) ? .busy : .unknown
            }
            guard let listenerPID, belongsToGroup(listenerPID) else { return .unknown }
            return .idle
        }
    }

    private func belongsToGroup(_ pid: Int32) -> Bool {
        pid > 0 && getpgid(pid) == handle.pid
    }

    func waitForExit(timeout: Duration) async throws -> RunnerProcessExit {
        let id = UUID()
        return try await withCheckedThrowingContinuation { continuation in
            let immediate = state.withLock { state -> RunnerProcessExit? in
                if let exit = state.exit { return exit }
                let timer = Task { [weak self] in
                    do { try await Task.sleep(for: timeout) }
                    catch { return }
                    self?.timeoutWaiter(id)
                }
                state.waiters[id] = ExitWaiter(continuation: continuation, timer: timer)
                return nil
            }
            if let immediate { continuation.resume(returning: immediate) }
        }
    }

    private func timeoutWaiter(_ id: UUID) {
        let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
        waiter?.continuation.resume(throwing: POSIXError(.ETIMEDOUT))
    }

    private func beginMonitoring() {
        let source = DispatchSource.makeProcessSource(identifier: handle.pid, eventMask: .exit,
            queue: DispatchQueue(label: "io.octorunner.process.\(handle.generation)"))
        source.setEventHandler { [self] in reap() }
        state.withLock { $0.source = source }
        source.resume()
        // Covers a process that exited before the event source was registered.
        reap()
    }

    private func reap() {
        let completion = state.withLock { state -> (RunnerProcessExit, [ExitWaiter], (any DispatchSourceProcess)?, (any DispatchSourceTimer)?)? in
            guard state.exit == nil else { return nil }
            var info = siginfo_t()
            var observation: Int32
            repeat { observation = waitid(P_PID, UInt32(handle.pid), &info, WEXITED | WNOHANG | WNOWAIT) }
            while observation == -1 && errno == EINTR
            guard observation == 0, info.si_pid == handle.pid else { return nil }
            // Keep the exited leader unreaped while its descendants are live.
            // The reserved PID keeps the group signal safe until the last member exits.
            if hasRemainingGroupMembers() {
                if state.groupTimer == nil {
                    let timer = DispatchSource.makeTimerSource()
                    timer.setEventHandler { [self] in reap() }
                    timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
                    state.groupTimer = timer
                    timer.resume()
                }
                return nil
            }
            var status: Int32 = 0
            var result: pid_t
            repeat { result = waitpid(handle.pid, &status, WNOHANG) } while result == -1 && errno == EINTR
            guard result == handle.pid else { return nil }
            let code = status & 0x7f == 0 ? (status >> 8) & 0xff : -(status & 0x7f)
            let exit = RunnerProcessExit(handle: handle, status: code)
            state.exit = exit
            let waiters = Array(state.waiters.values)
            state.waiters.removeAll()
            let source = state.source; state.source = nil
            let timer = state.groupTimer; state.groupTimer = nil
            return (exit, waiters, source, timer)
        }
        guard let (exit, waiters, source, timer) = completion else { return }
        source?.cancel()
        timer?.cancel()
        for reader in outputReaders { reader.finish() }
        terminal.continuation.yield(exit); terminal.continuation.finish()
        for waiter in waiters {
            waiter.timer.cancel()
            waiter.continuation.resume(returning: exit)
        }
    }

    private func hasRemainingGroupMembers() -> Bool {
        // Any full result necessarily contains a PID other than the group leader.
        var pids = [pid_t](repeating: 0, count: 16)
        let count = pids.withUnsafeMutableBytes { bytes in
            errno = 0
            return proc_listpids(UInt32(PROC_PGRP_ONLY), UInt32(handle.pid), bytes.baseAddress, Int32(bytes.count))
        }
        if count <= 0 { return count < 0 || errno != 0 }
        return pids.prefix(Int(count) / MemoryLayout<pid_t>.stride).contains { $0 > 0 && $0 != handle.pid }
    }

    private static func check(_ status: Int32) throws {
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EIO) }
    }
}
