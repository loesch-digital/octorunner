import CoreModels
import Foundation
@testable import RunnerEngine
import Testing

struct RunnerSupervisorTests {
    @Test("Storage cleanup reserves a stopped directory and cannot reserve a pending start")
    func storageReservation() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        let reserved = await supervisor.reserveStorage(roots: [config.rootDirectory])
        #expect(reserved.count == 1)
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.start(runnerID: config.runnerID)
        }
        await supervisor.releaseStorage(paths: reserved)
        let start = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.waitForStart()
        #expect(await supervisor.reserveStorage(roots: [config.rootDirectory]).isEmpty)
        await backend.release()
        try await start.value
        #expect(await supervisor.reserveStorage(roots: [config.rootDirectory]).isEmpty)
        try await supervisor.forceStop(runnerID: config.runnerID)
    }

    @Test("Quit and restart refuse to signal after a new sample finds a job")
    func refreshJobStateBeforeStopping() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend,
            activitySample: { _ in
                let pid = await backend.starts.last?.pid
                return (listenerPID: pid, workerPID: pid)
            })
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let handle = try #require(await backend.starts.last)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation, activity: .idle)
        await #expect(throws: RunnerSupervisionError.runnerBusy) { try await supervisor.shutdownForQuit() }
        await #expect(throws: RunnerSupervisionError.runnerBusy) { try await supervisor.restart(runnerID: config.runnerID) }
        #expect(await backend.stops.isEmpty)
    }

    @Test("Every launch checks that another service does not own the configured runner")
    func startChecksOwnership() async throws {
        let backend = SupervisorProcessFixture()
        let check = StartCheckFixture()
        let supervisor = RunnerSupervisorActor(processes: backend, startCheck: { try await check.validate($0) })
        let config = configuration()
        try await supervisor.configure(config)
        await #expect(throws: RunnerSupervisionError.notManaged) { try await supervisor.start(runnerID: config.runnerID) }
        #expect(await backend.starts.isEmpty)
        await check.setAllowed(true)
        try await supervisor.start(runnerID: config.runnerID)
        let handle = try #require(await backend.starts.last)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation, activity: .idle)
        await check.setAllowed(false)
        await #expect(throws: RunnerSupervisionError.notManaged) { try await supervisor.restart(runnerID: config.runnerID) }
        #expect(await backend.starts.count == 1)
        #expect(await check.attempts == [config, config, config])
    }

    @Test("Removal cannot hide a starting or running child and blocks stale requests after deletion")
    func reserveRemoval() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        let start = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.waitForStart()
        #expect(!(await supervisor.reserveRemoval(runnerID: config.runnerID)))
        await backend.release()
        try await start.value
        #expect(!(await supervisor.reserveRemoval(runnerID: config.runnerID)))
        try await supervisor.forceStop(runnerID: config.runnerID)
        #expect(await supervisor.reserveRemoval(runnerID: config.runnerID))
        await #expect(throws: RunnerSupervisionError.notManaged) { try await supervisor.configure(config) }
        await supervisor.finishRemoval(runnerID: config.runnerID, removed: false)
        try await supervisor.configure(config)
        #expect(await supervisor.reserveRemoval(runnerID: config.runnerID))
        await supervisor.finishRemoval(runnerID: config.runnerID, removed: true)
        await #expect(throws: RunnerSupervisionError.notManaged) { try await supervisor.configure(config) }
    }

    @Test("Process sampling cannot update a replacement generation")
    func oldProcessSample() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let first = try #require(await supervisor.processObservationTargets().first)
        #expect(first.rootPath == config.rootDirectory.path)
        try await supervisor.forceStop(runnerID: config.runnerID)
        try await supervisor.start(runnerID: config.runnerID)
        await supervisor.observeProcesses(first, listenerPID: first.handle.pid, workerPID: nil, observedAt: .now)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.activity == .unknown)
        let second = try #require(await supervisor.processObservationTargets().first)
        await supervisor.observeProcesses(second, listenerPID: second.handle.pid, workerPID: nil, observedAt: .now)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.activity == .idle)
    }

    @Test("Quit leaves every process untouched when one owned runner is busy")
    func quitRefusesBusyRunner() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let idle = configuration()
        let busy = configuration()
        for config in [idle, busy] {
            try await supervisor.configure(config)
            try await supervisor.start(runnerID: config.runnerID)
            let handle = try #require(await backend.starts.last)
            await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation,
                activity: config.runnerID == idle.runnerID ? .idle : .busy)
        }
        await #expect(throws: RunnerSupervisionError.runnerBusy) { try await supervisor.shutdownForQuit() }
        #expect(await backend.stops.isEmpty)
        let other = configuration()
        try await supervisor.configure(other)
        try await supervisor.start(runnerID: other.runnerID)
        #expect(await backend.starts.count == 3)
    }

    @Test("Confirmed quit stops idle owned runners and prevents overlapping starts")
    func quitStopsIdleRunner() async throws {
        let backend = SupervisorProcessFixture(gatedStop: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let owned = configuration()
        let other = configuration()
        for config in [owned, other] { try await supervisor.configure(config) }
        try await supervisor.start(runnerID: owned.runnerID)
        let handle = try #require(await backend.starts.last)
        await supervisor.updateActivity(runnerID: owned.runnerID, generation: handle.generation, activity: .idle)
        let quit = Task { try await supervisor.shutdownForQuit() }
        await backend.waitForStop()
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.start(runnerID: other.runnerID)
        }
        await backend.releaseStop()
        try await quit.value
        #expect(await backend.stops.map(\.force) == [false])
        #expect(await supervisor.snapshot(runnerID: owned.runnerID)?.phase == .stopped)
    }

    @Test("Concurrent repeated start launches one generation")
    func duplicateStart() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        let first = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.waitForStart()
        let second = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.release()
        try await first.value; try await second.value
        #expect(await backend.starts.count == 1)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .running)
    }

    @Test("A late exit from A never changes the restarted generation B")
    func lateExit() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let first = try #require(await backend.starts.first)
        try await supervisor.forceStop(runnerID: config.runnerID)
        try await supervisor.start(runnerID: config.runnerID)
        let second = try #require(await backend.starts.last)
        await supervisor.processExited(.init(handle: first, status: 1))
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.generation == second.generation)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .running)
        #expect(await backend.stops.count == 1)
    }

    @Test("Cancelled startup cleans up only its own new process")
    func cancelledStart() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        let task = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.waitForStart(); task.cancel(); await backend.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await backend.stops.count == 1)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
    }

    @Test("A failed startup cleanup retains the exact process for a later forced stop")
    func failedStartupCleanup() async throws {
        let backend = SupervisorProcessFixture(gated: true, failingFirstForcedStop: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        let startup = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.waitForStart()
        let handle = try #require(await backend.starts.first)
        startup.cancel()
        await backend.release()

        await #expect(throws: POSIXError(.ETIMEDOUT)) { try await startup.value }
        let snapshot = await supervisor.snapshot(runnerID: config.runnerID)
        #expect(snapshot?.pid == handle.pid)
        #expect(snapshot?.generation == handle.generation)
        try await supervisor.forceStop(runnerID: config.runnerID)
        #expect(await backend.stops.map(\.handle) == [handle, handle])
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
    }

    @Test("Unknown and external runners are never signalled")
    func ownership() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        try await supervisor.stop(runnerID: UUID())
        let external = configuration(mode: .external)
        try await supervisor.configure(external)
        await #expect(throws: RunnerSupervisionError.notManaged) { try await supervisor.start(runnerID: external.runnerID) }
        try? await supervisor.forceStop(runnerID: external.runnerID)
        #expect(await backend.starts.isEmpty)
        #expect(await backend.stops.isEmpty)
    }

    @Test("Drain timeout keeps a busy process running until a separately forced stop")
    func drainTimeout() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: try #require(await backend.starts.last).generation, activity: .busy)
        await #expect(throws: RunnerSupervisionError.runnerBusy) { try await supervisor.stop(runnerID: config.runnerID) }
        try await supervisor.requestDrain(runnerID: config.runnerID, now: .zero, timeout: .seconds(10))
        await supervisor.evaluateDrains(now: .seconds(10))
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .drainTimedOut)
        #expect(await backend.stops.isEmpty)
        try await supervisor.forceStop(runnerID: config.runnerID)
        #expect(await backend.stops.count == 1)
        #expect(await backend.stops.first?.force == true)
    }

    @Test("An idle observation completes a requested drain without force")
    func drainIdle() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: try #require(await backend.starts.last).generation, activity: .busy)
        try await supervisor.requestDrain(runnerID: config.runnerID, now: .zero, timeout: .seconds(10))
        await supervisor.updateActivity(runnerID: config.runnerID, generation: try #require(await backend.starts.last).generation, activity: .idle)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
        #expect(await backend.stops.first?.force == false)
    }

    @Test("A drain expires without any further activity observations", .timeLimit(.minutes(1)))
    func drainExpiresWithoutObservations() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        try await supervisor.requestDrain(runnerID: config.runnerID, timeout: .milliseconds(5))

        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while await supervisor.snapshot(runnerID: config.runnerID)?.phase == .draining,
              ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .drainTimedOut)
        #expect(await backend.stops.isEmpty)
    }

    @Test("A repeated stop cannot enqueue a second termination")
    func repeatedStop() async throws {
        let backend = SupervisorProcessFixture(gatedStop: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: try #require(await backend.starts.last).generation, activity: .idle)
        let first = Task { try await supervisor.stop(runnerID: config.runnerID) }
        await backend.waitForStop()
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.stop(runnerID: config.runnerID)
        }
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.requestDrain(runnerID: config.runnerID, timeout: .seconds(10))
        }
        await backend.releaseStop()
        try await first.value
        #expect(await backend.stops.count == 1)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
    }

    @Test("Drain waits for a fresh idle observation")
    func drainAwaitsFreshActivity() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let handle = try #require(await backend.starts.first)
        let now = ContinuousClock.now
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation,
            activity: .idle, observedAt: now.advanced(by: .seconds(-60)))
        try await supervisor.requestDrain(runnerID: config.runnerID, timeout: .seconds(10))
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation,
            activity: .idle, observedAt: now.advanced(by: .seconds(-30)))
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .draining)
        #expect(await backend.stops.isEmpty)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation, activity: .idle)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
    }

    @Test("A failed stop retains ownership and permits a separately confirmed forced stop")
    func failedStop() async throws {
        let backend = SupervisorProcessFixture(failingGracefulStop: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let handle = try #require(await backend.starts.first)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation, activity: .idle)

        await #expect(throws: POSIXError(.ETIMEDOUT)) { try await supervisor.stop(runnerID: config.runnerID) }
        let snapshot = await supervisor.snapshot(runnerID: config.runnerID)
        #expect(snapshot?.phase == .running)
        #expect(snapshot?.pid == handle.pid)
        try await supervisor.forceStop(runnerID: config.runnerID)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
    }

    @Test("An idle observation from an earlier generation cannot authorize stop")
    func staleGenerationActivity() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let first = try #require(await backend.starts.first)
        try await supervisor.forceStop(runnerID: config.runnerID)
        try await supervisor.start(runnerID: config.runnerID)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: first.generation, activity: .idle)
        await #expect(throws: RunnerSupervisionError.activityUnknown) { try await supervisor.stop(runnerID: config.runnerID) }
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .running)
        #expect(await backend.stops.count == 1)
    }

    @Test("Old and out-of-order idle observations cannot authorize stop")
    func staleActivity() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let handle = try #require(await backend.starts.first)
        let old = ContinuousClock.now.advanced(by: .seconds(-60))
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation, activity: .idle, observedAt: old)
        await #expect(throws: RunnerSupervisionError.activityUnknown) { try await supervisor.stop(runnerID: config.runnerID) }
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation, activity: .busy)
        await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation, activity: .idle, observedAt: old)
        await #expect(throws: RunnerSupervisionError.runnerBusy) { try await supervisor.stop(runnerID: config.runnerID) }
        #expect(await backend.stops.isEmpty)
    }

    private func configuration(mode: RunnerExecutionMode = .direct) -> ManagedRunnerConfiguration {
        .init(runnerID: UUID(), name: "fixture", rootDirectory: URL(filePath: "/tmp/owned-fixture"), mode: mode)
    }
}

private actor StartCheckFixture {
    private var allowed = false
    private(set) var attempts: [ManagedRunnerConfiguration] = []

    func setAllowed(_ allowed: Bool) { self.allowed = allowed }

    func validate(_ configuration: ManagedRunnerConfiguration) throws {
        attempts.append(configuration)
        guard allowed else { throw RunnerSupervisionError.notManaged }
    }
}

private actor SupervisorProcessFixture: RunnerProcessControlling {
    var starts: [RunnerProcessHandle] = []
    var stops: [(handle: RunnerProcessHandle, force: Bool)] = []
    private let gated: Bool
    private let gatedStop: Bool
    private let failingGracefulStop: Bool
    private let failingFirstForcedStop: Bool
    private let started = AsyncStream<Void>.makeStream()
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
    func release() { pending?.resume(); pending = nil }
    func waitForStop() async { for await _ in stopping.stream { return } }
    func releaseStop() { pendingStop?.resume(); pendingStop = nil }
}
