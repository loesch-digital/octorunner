import CoreModels
import Foundation
@testable import RunnerEngine
import Testing

struct RunnerSupervisorDrainTests {
    @Test("Drain timeout keeps a busy process running until a separately forced stop")
    func drainTimeout() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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
        let config = supervisorFixtureConfiguration()
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

    @Test("Drain waits for a fresh idle observation")
    func drainAwaitsFreshActivity() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
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
}
