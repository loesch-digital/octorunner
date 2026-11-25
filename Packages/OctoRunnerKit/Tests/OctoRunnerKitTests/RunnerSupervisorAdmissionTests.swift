import CoreModels
import Foundation
@testable import RunnerEngine
import Synchronization
import Testing

struct RunnerSupervisorAdmissionTests {
    @Test("With one slot, two concurrent start requests launch one runner and then admit the waiting runner",
          .timeLimit(.minutes(1)))
    func capacitySerializesStarts() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend, maximumConcurrentRunners: 1)
        let first = supervisorFixtureConfiguration()
        let second = supervisorFixtureConfiguration()
        try await supervisor.configure(first)
        try await supervisor.configure(second)
        let start = Task { try await supervisor.start(runnerID: first.runnerID) }
        await backend.waitForStart()
        try await supervisor.start(runnerID: second.runnerID)
        #expect(await supervisor.snapshot(runnerID: second.runnerID)?.phase == .waitingForCapacity)
        #expect(await backend.starts.count == 1)
        await backend.release()
        try await start.value
        let active = try #require(await backend.starts.first)
        await supervisor.processExited(.init(handle: active, status: 0))
        let waiting = try #require(await backend.nextStart(after: active))
        #expect(waiting.runnerID == second.runnerID)
    }

    @Test("Cancelling a queued start cannot cancel its newly queued replacement", .timeLimit(.minutes(1)))
    func cancelledCapacityTicket() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend, maximumConcurrentRunners: 1)
        let first = supervisorFixtureConfiguration()
        let second = supervisorFixtureConfiguration()
        try await supervisor.configure(first)
        try await supervisor.configure(second)
        try await supervisor.start(runnerID: first.runnerID)
        try await supervisor.start(runnerID: second.runnerID)
        let cancelled = try #require(await supervisor.snapshot(runnerID: second.runnerID)?.generation)
        try await supervisor.cancelPendingStart(runnerID: second.runnerID, expectedGeneration: cancelled)
        try await supervisor.start(runnerID: second.runnerID)
        let replacement = try #require(await supervisor.snapshot(runnerID: second.runnerID)?.generation)
        #expect(replacement != cancelled)
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.cancelPendingStart(runnerID: second.runnerID, expectedGeneration: cancelled)
        }
        let active = try #require(await backend.starts.first)
        await supervisor.processExited(.init(handle: active, status: 0))
        let launched = try #require(await backend.nextStart(after: active))
        #expect(launched.generation == replacement)
    }

    @Test("Failed launch releases the reserved slot so the oldest waiting runner can start",
          .timeLimit(.minutes(1)))
    func releaseCapacityOnFailure() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        let first = supervisorFixtureConfiguration()
        let second = supervisorFixtureConfiguration()
        let supervisor = RunnerSupervisorActor(processes: backend, startCheck: { configuration in
            if configuration.runnerID == first.runnerID {
                await gate.block()
                throw POSIXError(.EIO)
            }
        }, maximumConcurrentRunners: 1)
        try await supervisor.configure(first)
        try await supervisor.configure(second)
        let start = Task { try await supervisor.start(runnerID: first.runnerID) }
        await gate.waitUntilBlocked()
        try await supervisor.start(runnerID: second.runnerID)
        #expect(await supervisor.snapshot(runnerID: second.runnerID)?.phase == .waitingForCapacity)
        await gate.release()
        await #expect(throws: POSIXError(.EIO)) { try await start.value }
        let launched = try #require(await backend.firstLaunch())
        #expect(launched.runnerID == second.runnerID)
    }

    @Test("Lowering the limit does not signal busy runners or grant new capacity early", .timeLimit(.minutes(1)))
    func lowerRunnerCapacity() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend, maximumConcurrentRunners: 2)
        let first = supervisorFixtureConfiguration()
        let second = supervisorFixtureConfiguration()
        let third = supervisorFixtureConfiguration()
        for config in [first, second, third] { try await supervisor.configure(config) }
        try await supervisor.start(runnerID: first.runnerID)
        try await supervisor.start(runnerID: second.runnerID)
        let active = await backend.starts
        for handle in active {
            await supervisor.updateActivity(runnerID: handle.runnerID, generation: handle.generation, activity: .busy)
        }
        await supervisor.updateRecoveryPolicy(.init(), maximumConcurrentRunners: 1)
        try await supervisor.start(runnerID: third.runnerID)
        #expect(await backend.stops.isEmpty)
        await supervisor.processExited(.init(handle: active[0], status: 0))
        #expect(await supervisor.snapshot(runnerID: third.runnerID)?.phase == .waitingForCapacity)
        #expect(await supervisor.snapshot(runnerID: second.runnerID)?.activity == .busy)
        await supervisor.processExited(.init(handle: active[1], status: 0))
        let admitted = try #require(await backend.nextStart(after: active[1]))
        #expect(admitted.runnerID == third.runnerID)
    }

    @Test("Two direct configurations cannot reserve the same managed runner directory")
    func duplicateDirectory() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend, maximumConcurrentRunners: 2)
        let first = supervisorFixtureConfiguration()
        try await supervisor.configure(first)
        let duplicate = ManagedRunnerConfiguration(runnerID: UUID(), name: "duplicate",
            rootDirectory: first.rootDirectory, mode: .direct)
        await #expect(throws: RunnerSupervisionError.notManaged) { try await supervisor.configure(duplicate) }
    }

    @Test("Power resume reserves slots for older requests before a newer start can overtake them",
          .timeLimit(.minutes(1)), arguments: [false, true])
    func queuedPowerStartsKeepTheirOrder(notificationReceived: Bool) async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        let lowPower = Mutex(true)
        var policy = RunnerRuntimePolicy()
        policy.batterySaverEnabled = true
        let first = supervisorFixtureConfiguration()
        let second = supervisorFixtureConfiguration()
        let third = supervisorFixtureConfiguration()
        let supervisor = RunnerSupervisorActor(processes: backend, startCheck: { config in
            if config.runnerID == first.runnerID { await gate.block() }
        }, recoveryPolicy: policy, lowPowerMode: { lowPower.withLock { $0 } },
            maximumConcurrentRunners: 2)
        for config in [first, second, third] { try await supervisor.configure(config) }
        try await supervisor.start(runnerID: first.runnerID)
        try await supervisor.start(runnerID: second.runnerID)
        lowPower.withLock { $0 = false }
        var resume = notificationReceived ? Task { await supervisor.powerStateChanged() } : nil
        if notificationReceived { await gate.waitUntilBlocked() }
        try await supervisor.start(runnerID: third.runnerID)
        let thirdPhase = await supervisor.snapshot(runnerID: third.runnerID)?.phase
        if !notificationReceived {
            resume = Task { await supervisor.powerStateChanged() }
            await gate.waitUntilBlocked()
        }
        let secondPhase = await supervisor.snapshot(runnerID: second.runnerID)?.phase
        await gate.release()
        await resume?.value
        #expect(thirdPhase == .waitingForCapacity)
        #expect(secondPhase == .starting || secondPhase == .running)
    }

    @Test("Raising the limit reserves all free slots while the first queued launch is in preflight",
          .timeLimit(.minutes(1)))
    func raiseCapacityWithoutSerialPreflight() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        let active = supervisorFixtureConfiguration()
        let first = supervisorFixtureConfiguration()
        let second = supervisorFixtureConfiguration()
        let supervisor = RunnerSupervisorActor(processes: backend, startCheck: { config in
            if config.runnerID == first.runnerID { await gate.block() }
        }, maximumConcurrentRunners: 1)
        for config in [active, first, second] { try await supervisor.configure(config) }
        for config in [active, first, second] { try await supervisor.start(runnerID: config.runnerID) }
        let update = Task { await supervisor.updateRecoveryPolicy(.init(), maximumConcurrentRunners: 3) }
        await gate.waitUntilBlocked()
        let phase = await supervisor.snapshot(runnerID: second.runnerID)?.phase
        await gate.release()
        await update.value
        #expect(phase == .starting || phase == .running)
    }

    @Test("A policy observer cancellation does not revoke a manual start released by the policy", .timeLimit(.minutes(1)))
    func resumedStartOutlivesPolicyObserver() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        var energySaving = RunnerRuntimePolicy()
        energySaving.batterySaverEnabled = true
        let supervisor = RunnerSupervisorActor(processes: backend, startCheck: { _ in await gate.block() },
            recoveryPolicy: energySaving, lowPowerMode: { true })
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let update = Task { await supervisor.updateRecoveryPolicy(RunnerRuntimePolicy()) }
        await gate.waitUntilBlocked()
        update.cancel()
        var changed = RunnerRuntimePolicy()
        changed.restartDelaySeconds = 30
        await supervisor.updateRecoveryPolicy(changed)
        await gate.release()
        await update.value
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .running)
        #expect(await backend.starts.count == 1)
    }

    @Test("Low Power Mode defers new starts and leaves an existing child running")
    func lowPowerMode() async throws {
        let backend = SupervisorProcessFixture()
        let lowPower = Mutex(false)
        var policy = RunnerRuntimePolicy()
        policy.batterySaverEnabled = true
        let supervisor = RunnerSupervisorActor(processes: backend, recoveryPolicy: policy,
            lowPowerMode: { lowPower.withLock { $0 } })
        let active = supervisorFixtureConfiguration()
        let deferred = supervisorFixtureConfiguration()
        try await supervisor.configure(active)
        try await supervisor.configure(deferred)
        try await supervisor.start(runnerID: active.runnerID)
        lowPower.withLock { $0 = true }
        await supervisor.powerStateChanged()
        try await supervisor.start(runnerID: deferred.runnerID)
        #expect(await supervisor.snapshot(runnerID: deferred.runnerID)?.phase == .waitingForPower)
        #expect(await supervisor.snapshot(runnerID: active.runnerID)?.phase == .running)
        #expect(await backend.stops.isEmpty)
        #expect(await backend.starts.count == 1)
        lowPower.withLock { $0 = false }
        await supervisor.powerStateChanged()
        #expect(await supervisor.snapshot(runnerID: deferred.runnerID)?.phase == .running)
        #expect(await backend.starts.count == 2)
    }

    @Test("A deferred start is reconsidered when a storage reservation ends")
    func resumeAfterStorageReservation() async throws {
        let backend = SupervisorProcessFixture()
        let lowPower = Mutex(true)
        var policy = RunnerRuntimePolicy()
        policy.batterySaverEnabled = true
        let supervisor = RunnerSupervisorActor(processes: backend, recoveryPolicy: policy,
            lowPowerMode: { lowPower.withLock { $0 } })
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let lease = await supervisor.reserveIdleDirectories(roots: [config.rootDirectory])
        lowPower.withLock { $0 = false }
        await supervisor.powerStateChanged()
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .waitingForPower)
        await supervisor.releaseDirectories(paths: lease)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .running)
    }

    @Test("Cancelling a pending start is bound to the displayed generation")
    func cancelPendingStart() async throws {
        let backend = SupervisorProcessFixture()
        let lowPower = Mutex(true)
        var policy = RunnerRuntimePolicy()
        policy.batterySaverEnabled = true
        let supervisor = RunnerSupervisorActor(processes: backend, recoveryPolicy: policy,
            lowPowerMode: { lowPower.withLock { $0 } })
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        try await supervisor.start(runnerID: config.runnerID)
        let pending = try #require(await supervisor.snapshot(runnerID: config.runnerID)?.generation)
        try await supervisor.cancelPendingStart(runnerID: config.runnerID, expectedGeneration: pending)
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
        lowPower.withLock { $0 = false }
        await supervisor.powerStateChanged()
        #expect(await backend.starts.isEmpty)
        try await supervisor.start(runnerID: config.runnerID)
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.cancelPendingStart(runnerID: config.runnerID, expectedGeneration: pending)
        }
        #expect(await backend.stops.isEmpty)
    }

    @Test("Storage cleanup reserves a stopped directory and cannot reserve a pending start")
    func storageReservation() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = supervisorFixtureConfiguration()
        try await supervisor.configure(config)
        let reserved = await supervisor.reserveIdleDirectories(roots: [config.rootDirectory])
        #expect(reserved.count == 1)
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await supervisor.start(runnerID: config.runnerID)
        }
        await supervisor.releaseDirectories(paths: reserved)
        let start = Task { try await supervisor.start(runnerID: config.runnerID) }
        await backend.waitForStart()
        #expect(await supervisor.reserveIdleDirectories(roots: [config.rootDirectory]).isEmpty)
        await backend.release()
        try await start.value
        #expect(await supervisor.reserveIdleDirectories(roots: [config.rootDirectory]).isEmpty)
        try await supervisor.forceStop(runnerID: config.runnerID)
    }
}
