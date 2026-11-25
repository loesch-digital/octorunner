import CoreModels
import Foundation
@testable import RunnerEngine

func supervisorFixtureConfiguration(mode: RunnerExecutionMode = .direct) -> ManagedRunnerConfiguration {
    let id = UUID()
    return .init(runnerID: id, name: "fixture", rootDirectory: URL(filePath: "/tmp/owned-fixture-\(id)"), mode: mode)
}

actor StartCheckFixture {
    private var allowed = false
    private(set) var attempts: [ManagedRunnerConfiguration] = []

    func setAllowed(_ allowed: Bool) { self.allowed = allowed }

    func validate(_ configuration: ManagedRunnerConfiguration) throws {
        attempts.append(configuration)
        guard allowed else { throw RunnerSupervisionError.notManaged }
    }
}

actor SupervisorProcessFixture: RunnerProcessControlling {
    var starts: [RunnerProcessHandle] = []
    var stops: [(handle: RunnerProcessHandle, force: Bool)] = []
    private let gated: Bool
    private let gatedStop: Bool
    private let failingGracefulStop: Bool
    private let failingFirstForcedStop: Bool
    private let started = AsyncStream<Void>.makeStream()
    private let launches = AsyncStream<RunnerProcessHandle>.makeStream(bufferingPolicy: .bufferingNewest(1))
    private let stopping = AsyncStream<Void>.makeStream()
    private var pending: CheckedContinuation<Void, Never>?
    private var pendingStop: CheckedContinuation<Void, Never>?
    init(gated: Bool = false, gatedStop: Bool = false, failingGracefulStop: Bool = false,
         failingFirstForcedStop: Bool = false) {
        self.gated = gated
        self.gatedStop = gatedStop
        self.failingGracefulStop = failingGracefulStop
        self.failingFirstForcedStop = failingFirstForcedStop
    }
    func start(configuration: ManagedRunnerConfiguration, generation: UUID) async throws -> RunnerProcessHandle {
        let handle = RunnerProcessHandle(runnerID: configuration.runnerID, generation: generation,
            pid: Int32(starts.count + 100), startedAt: .now)
        starts.append(handle)
        launches.continuation.yield(handle)
        if gated && starts.count == 1 {
            await withCheckedContinuation { pending = $0; started.continuation.yield(()); started.continuation.finish() }
        }
        return handle
    }
    func stop(_ handle: RunnerProcessHandle, force: Bool) async throws -> RunnerProcessExit {
        stops.append((handle, force))
        if (failingGracefulStop && !force) || (failingFirstForcedStop && force && stops.count == 1) {
            throw POSIXError(.ETIMEDOUT)
        }
        if gatedStop && stops.count == 1 {
            await withCheckedContinuation { pendingStop = $0; stopping.continuation.yield(()); stopping.continuation.finish() }
        }
        return .init(handle: handle, status: 0)
    }
    func exits(for handle: RunnerProcessHandle) async -> AsyncStream<RunnerProcessExit> {
        AsyncStream { $0.finish() }
    }
    func activity(for handle: RunnerProcessHandle, listenerPID: Int32?, workerPID: Int32?) -> RunnerActivity {
        if workerPID == handle.pid { return .busy }
        return listenerPID == handle.pid ? .idle : .unknown
    }
    func waitForStart() async { for await _ in started.stream { return } }
    func nextStart(after previous: RunnerProcessHandle) async -> RunnerProcessHandle? {
        for await launch in launches.stream where launch.pid > previous.pid { return launch }
        return nil
    }
    func firstLaunch() async -> RunnerProcessHandle? {
        for await launch in launches.stream { return launch }
        return nil
    }
    func release() { pending?.resume(); pending = nil }
    func waitForStop() async { for await _ in stopping.stream { return } }
    func releaseStop() { pendingStop?.resume(); pendingStop = nil }
}

actor RestartClockFixture {
    private let waiters = AsyncStream<Duration>.makeStream()
    private var sleeper: CheckedContinuation<Void, Never>?

    func sleep(for delay: Duration) async throws {
        await withCheckedContinuation { continuation in
            sleeper = continuation
            waiters.continuation.yield(delay)
        }
        try Task.checkCancellation()
    }

    func advance() async -> Duration? {
        for await delay in waiters.stream {
            sleeper?.resume()
            sleeper = nil
            return delay
        }
        return nil
    }
}

actor RecoveryGate {
    private let entered = AsyncStream<Void>.makeStream()
    private var blocked: CheckedContinuation<Void, Never>?

    func block() async {
        await withCheckedContinuation { continuation in
            blocked = continuation
            entered.continuation.yield(())
            entered.continuation.finish()
        }
    }

    func waitUntilBlocked() async { for await _ in entered.stream { return } }

    func release() {
        blocked?.resume()
        blocked = nil
    }
}
