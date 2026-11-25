import CoreModels
import Foundation
@testable import RunnerEngine
import Testing

struct RunnerSupervisorRecoveryTests {
    @Test("An exit during voluntary stop preflight does not queue an automatic restart", .timeLimit(.minutes(1)))
    func exitDuringStopPreflight() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        let supervisor = RunnerSupervisorActor(processes: backend, activitySample: { _ in
            await gate.block()
            return (listenerPID: await backend.starts.first?.pid, workerPID: nil)
        }, recoveryPolicy: RunnerRuntimePolicy())
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let handle = try #require(await backend.starts.first)
        let stop = Task { try await supervisor.stop(runnerID: config.runnerID) }
        await gate.waitUntilBlocked()
        await supervisor.processExited(.init(handle: handle, status: 1))
        await gate.release()
        try await stop.value
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .faulted)
        #expect(await backend.starts.count == 1)
    }

    @Test("An old stop probe cannot suppress a replacement generation's recovery", .timeLimit(.minutes(1)))
    func replacementExitsWhileOldStopIsProbing() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        let supervisor = RunnerSupervisorActor(processes: backend, activitySample: { _ in
            await gate.block()
            return (listenerPID: await backend.starts.first?.pid, workerPID: nil)
        }, recoveryPolicy: RunnerRuntimePolicy())
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let first = try #require(await backend.starts.first)
        let stop = Task { try await supervisor.stop(runnerID: config.runnerID) }
        await gate.waitUntilBlocked()
        await supervisor.processExited(.init(handle: first, status: 1))
        try await supervisor.start(runnerID: config.runnerID)
        let second = try #require(await backend.starts.last)
        await supervisor.processExited(.init(handle: second, status: 1))
        await gate.release()
        try await stop.value
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .waitingToRestart)
        #expect(await backend.stops.isEmpty)
    }

    @Test("A failed preflight on a cancelled start cannot queue recovery", .timeLimit(.minutes(1)))
    func cancelledFailedStart() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        let supervisor = RunnerSupervisorActor(processes: backend, startCheck: { _ in
            await gate.block()
            throw POSIXError(.EIO)
        }, recoveryPolicy: RunnerRuntimePolicy())
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        let start = Task { try await supervisor.start(runnerID: config.runnerID) }
        await gate.waitUntilBlocked()
        start.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
        #expect(await backend.starts.isEmpty)
    }

    @Test("Automatic recovery restarts one generation and quarantines the next failure at the threshold",
          .timeLimit(.minutes(1)))
    func automaticRecovery() async throws {
        let backend = SupervisorProcessFixture()
        let clock = RestartClockFixture()
        var policy = RunnerRuntimePolicy()
        policy.quarantineThreshold = 2
        let supervisor = RunnerSupervisorActor(processes: backend, recoveryPolicy: policy,
            recoverySleep: { try await clock.sleep(for: $0) })
        var events = await supervisor.recoveryEvents().makeAsyncIterator()
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let first = try #require(await backend.starts.first)
        await supervisor.processExited(.init(handle: first, status: 1))
        #expect(await events.next()?.kind == .crash)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .waitingToRestart)
        #expect(await backend.starts.count == 1)
        #expect(await clock.advance() == .seconds(10))
        let second = try #require(await backend.nextStart(after: first))
        try await supervisor.start(runnerID: config.runnerID)
        await supervisor.processExited(.init(handle: second, status: 1))
        #expect(await events.next()?.kind == .quarantine)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .quarantined)
        try await supervisor.configure(config)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .quarantined)
        try await supervisor.start(runnerID: config.runnerID)
        #expect(await backend.starts.count == 3)
    }

    @Test("A late exit from A never changes the restarted generation B")
    func lateExit() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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

    @Test("A failed stop retains ownership and permits a separately confirmed forced stop")
    func failedStop() async throws {
        let backend = SupervisorProcessFixture(failingGracefulStop: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
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
}
