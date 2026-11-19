import CoreModels
import Foundation
@testable import RunnerEngine
import Synchronization
import Testing

struct RunnerSupervisorTests {
    @Test("With one slot, two concurrent start requests launch one runner and then admit the waiting runner",
          .timeLimit(.minutes(1)))
    func capacitySerializesStarts() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend, maximumConcurrentRunners: 1)
        let first = configuration()
        let second = configuration()
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
        let first = configuration()
        let second = configuration()
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
        let first = configuration()
        let second = configuration()
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
        let first = configuration()
        let second = configuration()
        let third = configuration()
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
        let first = configuration()
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
        let first = configuration()
        let second = configuration()
        let third = configuration()
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
        let active = configuration()
        let first = configuration()
        let second = configuration()
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

    @Test("An exit during voluntary stop preflight does not queue an automatic restart", .timeLimit(.minutes(1)))
    func exitDuringStopPreflight() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        let supervisor = RunnerSupervisorActor(processes: backend, activitySample: { _ in
            await gate.block()
            return (listenerPID: await backend.starts.first?.pid, workerPID: nil)
        }, recoveryPolicy: RunnerRuntimePolicy())
        let config = configuration()
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
        let config = configuration()
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
        let config = configuration()
        try await supervisor.configure(config)
        let start = Task { try await supervisor.start(runnerID: config.runnerID) }
        await gate.waitUntilBlocked()
        start.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await start.value }
        #expect(await supervisor.snapshot(runnerID: config.runnerID)?.phase == .stopped)
        #expect(await backend.starts.isEmpty)
    }

    @Test("A policy observer cancellation does not revoke a manual start released by the policy", .timeLimit(.minutes(1)))
    func resumedStartOutlivesPolicyObserver() async throws {
        let backend = SupervisorProcessFixture()
        let gate = RecoveryGate()
        var energySaving = RunnerRuntimePolicy()
        energySaving.batterySaverEnabled = true
        let supervisor = RunnerSupervisorActor(processes: backend, startCheck: { _ in await gate.block() },
            recoveryPolicy: energySaving, lowPowerMode: { true })
        let config = configuration()
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
        let active = configuration()
        let deferred = configuration()
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
        let config = configuration()
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
        let config = configuration()
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
        let config = configuration()
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

    @Test("A delayed confirmation cannot force-stop a replacement generation")
    func forceStopGeneration() async throws {
        let backend = SupervisorProcessFixture()
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
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

    @Test("Storage cleanup reserves a stopped directory and cannot reserve a pending start")
    func storageReservation() async throws {
        let backend = SupervisorProcessFixture(gated: true)
        let supervisor = RunnerSupervisorActor(processes: backend)
        let config = configuration()
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
        let id = UUID()
        return .init(runnerID: id, name: "fixture", rootDirectory: URL(filePath: "/tmp/owned-fixture-\(id)"), mode: mode)
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

private actor RestartClockFixture {
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

private actor RecoveryGate {
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
