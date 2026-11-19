import CoreModels
import Foundation
import ServiceManagement

public actor RunnerSupervisorActor: LoginItemServicing, RunnerServiceStateReading {
    private struct Runtime {
        var configuration: ManagedRunnerConfiguration
        var generation: UUID?
        var handle: RunnerProcessHandle?
        var phase: RunnerRuntimePhase = .stopped
        var activity: RunnerActivity = .unknown
        var activityObservedAt: ContinuousClock.Instant?
        var lastExitStatus: Int32?
        var cancelStart = false
        var deadline: Duration?
        var recoveryHistory = RunnerRestartHistory()
        var recoveryStartedAt: ContinuousClock.Instant?
        var automaticPowerStart = false

        func hasFreshIdleObservation(at now: ContinuousClock.Instant) -> Bool {
            guard activity == .idle, let activityObservedAt, activityObservedAt <= now else { return false }
            return activityObservedAt.duration(to: now) <= .seconds(20)
        }
    }
    private let processes: any RunnerProcessControlling
    private let startCheck: @Sendable (ManagedRunnerConfiguration) async throws -> Void
    private let activitySample: (@Sendable (URL) async throws -> (listenerPID: Int32?, workerPID: Int32?))?
    private let recoverySleep: @Sendable (Duration) async throws -> Void
    private let lowPowerMode: @Sendable () -> Bool
    private var recoveryPolicy: RunnerRuntimePolicy?
    private let origin = ContinuousClock.now
    private var runners: [UUID: Runtime] = [:]
    private var startingWaiters: [UUID: [CheckedContinuation<Void, any Error>]] = [:]
    private var monitors: [UUID: Task<Void, Never>] = [:]
    private var drainTimers: [UUID: Task<Void, Never>] = [:]
    private var recoveryTimers: [UUID: Task<Void, Never>] = [:]
    private let recoverySource = AsyncStream<RunnerRecoveryEvent>.makeStream()
    private var removedOrReserved: Set<UUID> = []
    private var stopChecks: [UUID: RunnerProcessHandle] = [:]
    private var reservedPaths: Set<String> = []
    private var isQuitting = false

    public init(
        processes: any RunnerProcessControlling = ManagedRunnerProcess(),
        startCheck: @escaping @Sendable (ManagedRunnerConfiguration) async throws -> Void = { _ in },
        activitySample: (@Sendable (URL) async throws -> (listenerPID: Int32?, workerPID: Int32?))? = nil,
        recoveryPolicy: RunnerRuntimePolicy? = nil,
        lowPowerMode: @escaping @Sendable () -> Bool = { false },
        recoverySleep: @escaping @Sendable (Duration) async throws -> Void = { try await ContinuousClock().sleep(for: $0) }
    ) {
        self.processes = processes
        self.startCheck = startCheck
        self.activitySample = activitySample
        self.recoveryPolicy = recoveryPolicy?.validated()
        self.recoverySleep = recoverySleep
        self.lowPowerMode = lowPowerMode
    }
    deinit {
        for task in monitors.values { task.cancel() }
        for task in drainTimers.values { task.cancel() }
        for task in recoveryTimers.values { task.cancel() }
        recoverySource.continuation.finish()
    }

    public func configure(_ configuration: ManagedRunnerConfiguration) throws {
        guard !removedOrReserved.contains(configuration.runnerID) else { throw RunnerSupervisionError.notManaged }
        guard !configuration.name.isEmpty, configuration.rootDirectory.isFileURL else { throw RunnerSupervisionError.invalidConfiguration }
        if let runtime = runners[configuration.runnerID] {
            if runtime.configuration == configuration { return }
            guard runtime.handle == nil, runtime.phase != .starting else { throw RunnerSupervisionError.operationInProgress }
        }
        recoveryTimers.removeValue(forKey: configuration.runnerID)?.cancel()
        runners[configuration.runnerID] = Runtime(configuration: configuration)
    }

    public func snapshot(runnerID: UUID) -> RunnerRuntimeSnapshot? {
        guard let runtime = runners[runnerID] else { return nil }
        return .init(runnerID: runnerID, mode: runtime.configuration.mode, generation: runtime.generation,
            pid: runtime.handle?.pid, startedAt: runtime.handle?.startedAt, phase: runtime.phase,
            activity: runtime.activity, lastExitStatus: runtime.lastExitStatus)
    }

    public func processObservationTargets() -> [RunnerProcessObservationTarget] {
        runners.values.compactMap { runtime in
            runtime.handle.map {
                RunnerProcessObservationTarget(rootPath: runtime.configuration.rootDirectory.standardizedFileURL.path, handle: $0)
            }
        }
    }

    public func runtimePhases() -> [UUID: RunnerRuntimePhase] {
        runners.mapValues(\.phase)
    }

    /// One app-lifetime consumer. Events carry lifecycle metadata only.
    public func recoveryEvents() -> AsyncStream<RunnerRecoveryEvent> { recoverySource.stream }

    public func observeProcesses(_ target: RunnerProcessObservationTarget, listenerPID: Int32?,
                                 workerPID: Int32?, observedAt: ContinuousClock.Instant) async {
        let handle = target.handle
        guard !Task.isCancelled, runners[handle.runnerID]?.handle == handle else { return }
        let activity = await processes.activity(for: handle, listenerPID: listenerPID, workerPID: workerPID)
        guard !Task.isCancelled else { return }
        await updateActivity(runnerID: handle.runnerID, generation: handle.generation, activity: activity, observedAt: observedAt)
    }

    public func start(runnerID: UUID) async throws {
        try await start(runnerID: runnerID, automatic: false)
    }

    private func start(runnerID: UUID, automatic: Bool) async throws {
        try Task.checkCancellation()
        guard !isQuitting else { throw RunnerSupervisionError.operationInProgress }
        guard !removedOrReserved.contains(runnerID) else { throw RunnerSupervisionError.notManaged }
        guard let runtime = runners[runnerID], runtime.configuration.mode == .direct else { throw RunnerSupervisionError.notManaged }
        guard !reservedPaths.contains(runtime.configuration.rootDirectory.standardizedFileURL.path) else {
            throw RunnerSupervisionError.operationInProgress
        }
        if runtime.phase == .starting, let generation = runtime.generation {
            try await waitForStart(generation)
            try Task.checkCancellation()
            return
        }
        if runtime.phase == .stopping { throw RunnerSupervisionError.operationInProgress }
        if runtime.handle != nil { return }
        if !automatic {
            recoveryTimers.removeValue(forKey: runnerID)?.cancel()
            runners[runnerID]?.recoveryHistory = RunnerRestartHistory()
        }
        let generation = UUID()
        runners[runnerID]?.generation = generation
        if deferForPower(runnerID: runnerID, automatic: automatic) { return }
        runners[runnerID]?.phase = .starting
        runners[runnerID]?.cancelStart = false
        do {
            try await startCheck(runtime.configuration)
            try Task.checkCancellation()
            if runners[runnerID]?.cancelStart == true { throw CancellationError() }
            if automatic, !allowsRecovery(status: runtime.lastExitStatus) { throw CancellationError() }
            if deferForPower(runnerID: runnerID, automatic: automatic) {
                finishStart(generation, result: .success(()))
                return
            }
            runners[runnerID]?.lastExitStatus = nil
            let handle = try await processes.start(configuration: runtime.configuration, generation: generation)
            runners[runnerID]?.handle = handle
            runners[runnerID]?.phase = .running
            runners[runnerID]?.activity = .unknown
            runners[runnerID]?.recoveryStartedAt = .now
            monitors[runnerID] = Task { [weak self, processes] in
                let events = await processes.exits(for: handle)
                for await exit in events {
                    guard !Task.isCancelled else { return }
                    await self?.processExited(exit)
                }
            }
            if Task.isCancelled || runners[runnerID]?.cancelStart == true {
                try await stop(runnerID: runnerID, force: true)
                throw CancellationError()
            }
            finishStart(generation, result: .success(()))
        } catch {
            if runners[runnerID]?.generation == generation, runners[runnerID]?.phase == .starting {
                if Task.isCancelled || runners[runnerID]?.cancelStart == true || error is CancellationError {
                    runners[runnerID]?.phase = .stopped
                    let cancellation = CancellationError()
                    finishStart(generation, result: .failure(cancellation))
                    throw cancellation
                }
                runners[runnerID]?.phase = .faulted
                runners[runnerID]?.lastExitStatus = nil
                considerRecovery(runnerID: runnerID, generation: generation, status: nil, uptime: .zero, intentional: false)
            }
            finishStart(generation, result: .failure(error))
            throw error
        }
    }

    public func stop(runnerID: UUID) async throws { try await stop(runnerID: runnerID, force: false) }
    public func forceStop(runnerID: UUID, expectedGeneration: UUID? = nil) async throws {
        if let expectedGeneration, runners[runnerID]?.handle?.generation != expectedGeneration {
            throw RunnerSupervisionError.operationInProgress
        }
        try await stop(runnerID: runnerID, force: true)
    }
    public func restart(runnerID: UUID) async throws {
        try await stop(runnerID: runnerID)
        try Task.checkCancellation()
        try await start(runnerID: runnerID)
    }

    public func cancelPendingStart(runnerID: UUID, expectedGeneration: UUID) throws {
        guard let runtime = runners[runnerID], runtime.generation == expectedGeneration,
              runtime.phase == .waitingToRestart || runtime.phase == .waitingForPower else {
            throw RunnerSupervisionError.operationInProgress
        }
        cancelScheduledRestart(runnerID: runnerID)
    }

    public func updateRecoveryPolicy(_ settings: RunnerRuntimePolicy) async {
        guard !Task.isCancelled else { return }
        let settings = settings.validated()
        recoveryPolicy = settings
        for (id, runtime) in runners where runtime.phase == .waitingToRestart
            || (runtime.phase == .waitingForPower && runtime.automaticPowerStart) {
            if !allowsRecovery(status: runtime.lastExitStatus) {
                cancelScheduledRestart(runnerID: id)
            }
        }
        await powerStateChanged()
    }

    private func allowsRecovery(status: Int32?) -> Bool {
        switch recoveryPolicy?.restartPolicy {
        case .always: true
        case .onNonZeroExit: status != 0
        case .manual, nil: false
        }
    }

    private func deferForPower(runnerID: UUID, automatic: Bool) -> Bool {
        guard recoveryPolicy?.batterySaverEnabled == true, lowPowerMode() else { return false }
        runners[runnerID]?.automaticPowerStart = automatic
        runners[runnerID]?.phase = .waitingForPower
        return true
    }

    public func powerStateChanged() async {
        guard !Task.isCancelled, !isQuitting,
              recoveryPolicy?.batterySaverEnabled != true || !lowPowerMode() else { return }
        // A released start belongs to the supervisor. Replacing a preferences
        // observer task must not revoke an already accepted start.
        await Task { await resumePowerStarts() }.value
    }

    private func resumePowerStarts() async {
        let pending = runners.filter { $0.value.phase == .waitingForPower }
        for (id, runtime) in pending {
            guard !Task.isCancelled else { return }
            guard runners[id]?.phase == .waitingForPower, runners[id]?.generation == runtime.generation else { continue }
            try? await start(runnerID: id, automatic: runtime.automaticPowerStart)
        }
    }

    public func reserveRemoval(runnerID: UUID) -> Bool {
        guard runners[runnerID]?.handle == nil, runners[runnerID]?.phase != .starting else { return false }
        guard removedOrReserved.insert(runnerID).inserted else { return false }
        cancelScheduledRestart(runnerID: runnerID)
        return true
    }

    public func finishRemoval(runnerID: UUID, removed: Bool) {
        if removed { runners.removeValue(forKey: runnerID) }
        else { removedOrReserved.remove(runnerID) }
    }

    public func reserveIdleDirectories(roots: [URL]) -> Set<String> {
        let activePaths = Set(runners.values.compactMap { runtime -> String? in
            guard runtime.handle != nil || runtime.phase == .starting else { return nil }
            return runtime.configuration.rootDirectory.standardizedFileURL.path
        })
        let available = Set(roots.map { $0.standardizedFileURL.path }).subtracting(activePaths).subtracting(reservedPaths)
        reservedPaths.formUnion(available)
        return available
    }

    public func releaseDirectories(paths: Set<String>) async {
        reservedPaths.subtract(paths)
        await powerStateChanged()
    }

    /// Freeze new starts and preflight every current child before requesting
    /// termination. Each individual stop revalidates its activity after awaits.
    public func shutdownForQuit() async throws {
        try Task.checkCancellation()
        guard !isQuitting else { throw RunnerSupervisionError.operationInProgress }
        let active = runners.filter { $0.value.handle != nil || $0.value.phase == .starting }
        isQuitting = true
        do {
            for (id, runtime) in active {
                guard runtime.phase != .starting, runtime.phase != .stopping,
                      stopChecks[id] != runtime.handle else {
                    throw RunnerSupervisionError.operationInProgress
                }
                _ = try await confirmIdle(runnerID: id, runtime: runtime)
            }
            for id in active.keys {
                try Task.checkCancellation()
                try await stop(runnerID: id)
            }
            for id in Array(runners.keys) { cancelScheduledRestart(runnerID: id) }
        } catch {
            isQuitting = false
            await powerStateChanged()
            throw error
        }
    }

    private func stop(runnerID: UUID, force: Bool) async throws {
        guard let runtime = runners[runnerID] else { return }
        guard runtime.configuration.mode == .direct else { throw RunnerSupervisionError.notManaged }
        if runtime.phase == .starting, let generation = runtime.generation {
            runners[runnerID]?.cancelStart = true
            do { try await waitForStart(generation) }
            catch is CancellationError { return }
            return
        }
        guard let handle = runtime.handle else {
            cancelScheduledRestart(runnerID: runnerID)
            return
        }
        guard runtime.phase != .stopping, stopChecks[runnerID] != handle else {
            throw RunnerSupervisionError.operationInProgress
        }
        stopChecks[runnerID] = handle
        defer {
            if stopChecks[runnerID] == handle { stopChecks.removeValue(forKey: runnerID) }
        }
        if !force {
            guard try await confirmIdle(runnerID: runnerID, runtime: runtime) else { return }
            guard runtime.phase != .draining || runners[runnerID]?.phase == .draining else {
                throw RunnerSupervisionError.operationInProgress
            }
        }
        runners[runnerID]?.phase = .stopping
        drainTimers.removeValue(forKey: runnerID)?.cancel()
        do {
            let exit = try await processes.stop(handle, force: force)
            processExited(exit)
        } catch {
            if runners[runnerID]?.handle == handle, runners[runnerID]?.phase == .stopping {
                runners[runnerID]?.phase = runtime.phase == .draining ? .drainTimedOut : runtime.phase
            }
            throw error
        }
    }

    private static func requireIdle(_ runtime: Runtime, at now: ContinuousClock.Instant) throws {
        guard runtime.activity != .busy else { throw RunnerSupervisionError.runnerBusy }
        guard runtime.hasFreshIdleObservation(at: now) else { throw RunnerSupervisionError.activityUnknown }
    }

    private func confirmIdle(runnerID: UUID, runtime: Runtime) async throws -> Bool {
        guard let handle = runtime.handle else { return false }
        guard let activitySample else {
            try Self.requireIdle(runtime, at: .now)
            return true
        }
        let sampledAt = ContinuousClock.now
        let sample = try await activitySample(runtime.configuration.rootDirectory)
        let activity = await processes.activity(for: handle, listenerPID: sample.listenerPID, workerPID: sample.workerPID)
        try Task.checkCancellation()
        guard var current = runners[runnerID], current.handle == handle else { return false }
        if current.activityObservedAt.map({ $0 <= sampledAt }) ?? true {
            current.activity = activity
            current.activityObservedAt = sampledAt
            runners[runnerID] = current
        }
        guard activity != .busy else { throw RunnerSupervisionError.runnerBusy }
        guard activity == .idle else { throw RunnerSupervisionError.activityUnknown }
        try Self.requireIdle(current, at: .now)
        return true
    }

    func processExited(_ exit: RunnerProcessExit) {
        let id = exit.handle.runnerID
        guard let runtime = runners[id], runtime.handle == exit.handle, runtime.generation == exit.handle.generation else { return }
        runners[id]?.lastExitStatus = exit.status
        runners[id]?.phase = runtime.phase == .stopping || exit.status == 0 ? .stopped : .faulted
        runners[id]?.handle = nil
        runners[id]?.activity = .unknown
        runners[id]?.activityObservedAt = nil
        runners[id]?.deadline = nil
        runners[id]?.recoveryStartedAt = nil
        drainTimers.removeValue(forKey: id)?.cancel()
        monitors.removeValue(forKey: id)?.cancel()
        let intendedStop = stopChecks[id] == exit.handle || [.stopping, .draining, .drainTimedOut].contains(runtime.phase)
        let uptime = runtime.recoveryStartedAt?.duration(to: .now) ?? .zero
        considerRecovery(runnerID: id, generation: exit.handle.generation, status: exit.status, uptime: uptime, intentional: intendedStop)
    }

    private func considerRecovery(runnerID: UUID, generation: UUID, status: Int32?, uptime: Duration, intentional: Bool) {
        guard let recoveryPolicy, var runtime = runners[runnerID] else { return }
        let decision = runtime.recoveryHistory.record(settings: recoveryPolicy, status: status, uptime: uptime, intentional: intentional)
        let shouldNotifyCrash = !intentional && status != 0 && runtime.recoveryHistory.markFirstCrash()
        runners[runnerID] = runtime
        switch decision {
        case .stop: break
        case .quarantine: runners[runnerID]?.phase = .quarantined
        case .retry(let delay): scheduleRestart(runnerID: runnerID, generation: generation, delay: delay)
        }
        if decision == .quarantine {
            recoverySource.continuation.yield(.init(runnerID: runnerID, runnerName: runtime.configuration.name,
                generation: generation, kind: .quarantine, exitStatus: status, shouldNotify: true))
        } else if !intentional, status != 0 {
            recoverySource.continuation.yield(.init(runnerID: runnerID, runnerName: runtime.configuration.name,
                generation: generation, kind: .crash, exitStatus: status, shouldNotify: shouldNotifyCrash))
        }
    }

    private func scheduleRestart(runnerID: UUID, generation: UUID, delay: Duration) {
        runners[runnerID]?.phase = .waitingToRestart
        recoveryTimers[runnerID] = Task { [weak self, recoverySleep] in
            do {
                try await recoverySleep(delay)
                try Task.checkCancellation()
            } catch { return }
            await self?.resumeRecovery(runnerID: runnerID, generation: generation, delay: delay)
        }
    }

    private func resumeRecovery(runnerID: UUID, generation: UUID, delay: Duration) async {
        guard !Task.isCancelled, let runtime = runners[runnerID], runtime.generation == generation,
              runtime.phase == .waitingToRestart else { return }
        recoveryTimers.removeValue(forKey: runnerID)
        if isQuitting || reservedPaths.contains(runtime.configuration.rootDirectory.standardizedFileURL.path) {
            scheduleRestart(runnerID: runnerID, generation: generation, delay: delay)
            return
        }
        // A failed spawn is counted by start(), where its generation is still current.
        try? await start(runnerID: runnerID, automatic: true)
    }

    private func cancelScheduledRestart(runnerID: UUID) {
        recoveryTimers.removeValue(forKey: runnerID)?.cancel()
        if let phase = runners[runnerID]?.phase, phase == .waitingToRestart || phase == .waitingForPower {
            runners[runnerID]?.phase = .stopped
            runners[runnerID]?.recoveryHistory = RunnerRestartHistory()
        }
    }

    func updateActivity(runnerID: UUID, generation: UUID, activity: RunnerActivity,
        observedAt: ContinuousClock.Instant = .now) async {
        let now = ContinuousClock.now
        guard let runtime = runners[runnerID], runtime.handle != nil, runtime.generation == generation,
              observedAt <= now else { return }
        if let previous = runtime.activityObservedAt, observedAt < previous { return }
        runners[runnerID]?.activity = activity
        runners[runnerID]?.activityObservedAt = observedAt
        if drainTimers[runnerID] != nil, let deadline = runtime.deadline,
           deadline <= origin.duration(to: now) {
            expireDrain(runnerID: runnerID, deadline: deadline)
        }
        if runners[runnerID]?.phase == .draining, runners[runnerID]?.hasFreshIdleObservation(at: now) == true {
            // stop restores an appropriate phase if the process rejects termination.
            try? await stop(runnerID: runnerID)
        }
    }

    public func requestDrain(runnerID: UUID, timeout: Duration) async throws {
        try await requestDrain(runnerID: runnerID, now: nil, timeout: timeout)
    }

    func requestDrain(runnerID: UUID, now: Duration?, timeout: Duration) async throws {
        guard let runtime = runners[runnerID], runtime.configuration.mode == .direct else { throw RunnerSupervisionError.notManaged }
        guard runtime.phase != .starting, runtime.phase != .stopping, runtime.phase != .draining else {
            throw RunnerSupervisionError.operationInProgress
        }
        guard runtime.handle != nil else { return }
        guard timeout > .zero, timeout <= .seconds(3600) else { throw RunnerSupervisionError.invalidConfiguration }
        let deadline = (now ?? origin.duration(to: .now)) + timeout
        runners[runnerID]?.deadline = deadline
        runners[runnerID]?.phase = .draining
        if now == nil {
            let wakeUp = origin.advanced(by: deadline)
            drainTimers[runnerID] = Task { [weak self] in
                do { try await ContinuousClock().sleep(until: wakeUp) }
                catch { return }
                await self?.expireDrain(runnerID: runnerID, deadline: deadline)
            }
        }
        if runtime.hasFreshIdleObservation(at: .now) {
            do { try await stop(runnerID: runnerID) }
            catch RunnerSupervisionError.runnerBusy {}
            catch RunnerSupervisionError.activityUnknown {}
        }
    }

    func evaluateDrains(now: Duration) {
        for (id, runtime) in runners where runtime.phase == .draining {
            if let deadline = runtime.deadline, deadline <= now { expireDrain(runnerID: id, deadline: deadline) }
        }
    }

    private func expireDrain(runnerID: UUID, deadline: Duration) {
        guard runners[runnerID]?.phase == .draining, runners[runnerID]?.deadline == deadline else { return }
        runners[runnerID]?.phase = .drainTimedOut
        runners[runnerID]?.deadline = nil
        drainTimers.removeValue(forKey: runnerID)?.cancel()
    }

    private func waitForStart(_ generation: UUID) async throws {
        try await withCheckedThrowingContinuation { startingWaiters[generation, default: []].append($0) }
    }
    private func finishStart(_ generation: UUID, result: Result<Void, any Error>) {
        for continuation in startingWaiters.removeValue(forKey: generation) ?? [] { continuation.resume(with: result) }
    }


    public nonisolated func isUnloaded(label: String) async throws -> Bool {
        try await LaunchAgentServiceStateReader().isUnloaded(label: label)
    }

    public func status() -> LoginItemState {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .disabled
        case .notFound: .unavailable
        @unknown default: .unavailable
        }
    }

    public func setEnabled(_ enabled: Bool) async throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }

    public func isLoginAutostartEnabled() -> Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setLoginAutostart(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
