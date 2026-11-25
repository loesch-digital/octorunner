import CoreModels
import Foundation
@testable import RunnerEngine
import Testing

struct RunnerSupervisorLifecycleTests {
    @Test("A delayed confirmation cannot force-stop a replacement generation")
    func forceStopGeneration() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let first = try #require(await backend.starts.first)
        try await supervisor.forceStop(runnerID: config.runnerID)
        try await supervisor.start(runnerID: config.runnerID)
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.forceStop(runnerID: config.runnerID, expectedGeneration: first.generation)
        }
        #expect(await backend.stops.count == 1)
    }

    @Test("Quit and restart refuse to signal after a new sample finds a job")
    func refreshJobStateBeforeStopping() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend,
            activitySample: { _ in
                let pid = await backend.starts.last?.pid
                return (listenerPID: pid, workerPID: pid)
            })
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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
        let idle = supervisorFixtureConfiguration()
        let busy = supervisorFixtureConfiguration()
        for config in [idle, busy] {
            try await supervisor.configure(config)
            try await supervisor.start(runnerID: config.runnerID)
            let handle = try #require(await backend.starts.last)
            await supervisor.updateActivity(runnerID: config.runnerID, generation: handle.generation,
                activity: config.runnerID == idle.runnerID ? .idle : .busy)
        }
        await #expect(throws: RunnerSupervisionError.runnerBusy) { try await supervisor.shutdownForQuit() }
        #expect(await backend.stops.isEmpty)
        let other = supervisorFixtureConfiguration()
        try await supervisor.configure(other)
        try await supervisor.start(runnerID: other.runnerID)
        #expect(await backend.starts.count == 3)
    }

    @Test("Confirmed quit stops idle owned runners and prevents overlapping starts")
    func quitStopsIdleRunner() async throws {
        let backend = SupervisorProcessFixture(gatedStop: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let owned = supervisorFixtureConfiguration()
        let other = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        let first = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.waitForStart()
        let second = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.release()
        try await first.value; try await second.value
        #expect(await backend.starts.count == 1)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .running)
    }

    @Test("Unknown and external runners are never signalled")
    func ownership() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        try await supervisor.stop(runnerID: UUID())
        let external = supervisorFixtureConfiguration(mode: .external)
        try await supervisor.configure(external)
        await #expect(throws: RunnerSupervisionError.notManaged) { try await supervisor.start(runnerID: external.runnerID) }
        try? await supervisor.forceStop(runnerID: external.runnerID)
        #expect(await backend.starts.isEmpty)
        #expect(await backend.stops.isEmpty)
    }

    @Test("A repeated stop cannot enqueue a second termination")
    func repeatedStop() async throws {
        let backend = SupervisorProcessFixture(gatedStop: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
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

    @Test("An idle observation from an earlier generation cannot authorize stop")
    func staleGenerationActivity() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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
}
