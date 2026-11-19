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

        func hasFreshIdleObservation(at now: ContinuousClock.Instant) -> Bool {
            guard activity == .idle, let activityObservedAt, activityObservedAt <= now else { return false }
            return activityObservedAt.duration(to: now) <= .seconds(20)
        }
    }
    private let processes: any RunnerProcessControlling
    private let startCheck: @Sendable (ManagedRunnerConfiguration) async throws -> Void
    private let activitySample: (@Sendable (URL) async throws -> (listenerPID: Int32?, workerPID: Int32?))?
    private let origin = ContinuousClock.now
    private var runners: [UUID: Runtime] = [:]
    private var startingWaiters: [UUID: [CheckedContinuation<Void, any Error>]] = [:]
    private var monitors: [UUID: Task<Void, Never>] = [:]
    private var drainTimers: [UUID: Task<Void, Never>] = [:]
    private var removedOrReserved: Set<UUID> = []
    private var stopChecks: Set<UUID> = []
    private var storagePaths: Set<String> = []
    private var isQuitting = false

    public init(
        processes: any RunnerProcessControlling = ManagedRunnerProcess(),
        startCheck: @escaping @Sendable (ManagedRunnerConfiguration) async throws -> Void = { _ in },
        activitySample: (@Sendable (URL) async throws -> (listenerPID: Int32?, workerPID: Int32?))? = nil
    ) {
        self.processes = processes
        self.startCheck = startCheck
        self.activitySample = activitySample
    }
    deinit {
        for task in monitors.values { task.cancel() }
        for task in drainTimers.values { task.cancel() }
    }

    public func configure(_ configuration: ManagedRunnerConfiguration) throws {
        guard !removedOrReserved.contains(configuration.runnerID) else { throw RunnerSupervisionError.notManaged }
        guard !configuration.name.isEmpty, configuration.rootDirectory.isFileURL else { throw RunnerSupervisionError.invalidConfiguration }
        if let runtime = runners[configuration.runnerID], runtime.handle != nil || runtime.phase == .starting {
            guard runtime.configuration == configuration else { throw RunnerSupervisionError.operationInProgress }
            return
        }
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

    public func observeProcesses(_ target: RunnerProcessObservationTarget, listenerPID: Int32?,
                                 workerPID: Int32?, observedAt: ContinuousClock.Instant) async {
        let handle = target.handle
        guard !Task.isCancelled, runners[handle.runnerID]?.handle == handle else { return }
        let activity = await processes.activity(for: handle, listenerPID: listenerPID, workerPID: workerPID)
        guard !Task.isCancelled else { return }
        await updateActivity(runnerID: handle.runnerID, generation: handle.generation, activity: activity, observedAt: observedAt)
    }

    public func start(runnerID: UUID) async throws {
        try Task.checkCancellation()
        guard !isQuitting else { throw RunnerSupervisionError.operationInProgress }
        guard !removedOrReserved.contains(runnerID) else { throw RunnerSupervisionError.notManaged }
        guard let runtime = runners[runnerID], runtime.configuration.mode == .direct else { throw RunnerSupervisionError.notManaged }
        guard !storagePaths.contains(runtime.configuration.rootDirectory.standardizedFileURL.path) else {
            throw RunnerSupervisionError.operationInProgress
        }
        if runtime.phase == .starting, let generation = runtime.generation {
            try await waitForStart(generation)
            try Task.checkCancellation()
            return
        }
        if runtime.phase == .stopping { throw RunnerSupervisionError.operationInProgress }
        if runtime.handle != nil { return }
        let generation = UUID()
        runners[runnerID]?.generation = generation
        runners[runnerID]?.phase = .starting
        runners[runnerID]?.lastExitStatus = nil
        runners[runnerID]?.cancelStart = false
        do {
            try await startCheck(runtime.configuration)
            try Task.checkCancellation()
            if runners[runnerID]?.cancelStart == true { throw CancellationError() }
            let handle = try await processes.start(configuration: runtime.configuration, generation: generation)
            runners[runnerID]?.handle = handle
            runners[runnerID]?.phase = .running
            runners[runnerID]?.activity = .unknown
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
                runners[runnerID]?.phase = error is CancellationError ? .stopped : .faulted
            }
            finishStart(generation, result: .failure(error))
            throw error
        }
    }

    public func stop(runnerID: UUID) async throws { try await stop(runnerID: runnerID, force: false) }
    public func forceStop(runnerID: UUID) async throws { try await stop(runnerID: runnerID, force: true) }
    public func restart(runnerID: UUID) async throws {
        try await stop(runnerID: runnerID)
        try Task.checkCancellation()
        try await start(runnerID: runnerID)
    }

    public func reserveRemoval(runnerID: UUID) -> Bool {
        guard runners[runnerID]?.handle == nil, runners[runnerID]?.phase != .starting else { return false }
        return removedOrReserved.insert(runnerID).inserted
    }

    public func finishRemoval(runnerID: UUID, removed: Bool) {
        if removed { runners.removeValue(forKey: runnerID) }
        else { removedOrReserved.remove(runnerID) }
    }

    public func reserveStorage(roots: [URL]) -> Set<String> {
        let activePaths = Set(runners.values.compactMap { runtime -> String? in
            guard runtime.handle != nil || runtime.phase == .starting else { return nil }
            return runtime.configuration.rootDirectory.standardizedFileURL.path
        })
        let available = Set(roots.map { $0.standardizedFileURL.path }).subtracting(activePaths).subtracting(storagePaths)
        storagePaths.formUnion(available)
        return available
    }

    public func releaseStorage(paths: Set<String>) {
        storagePaths.subtract(paths)
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
                guard runtime.phase != .starting, runtime.phase != .stopping, !stopChecks.contains(id) else {
                    throw RunnerSupervisionError.operationInProgress
                }
                _ = try await confirmIdle(runnerID: id, runtime: runtime)
            }
            for id in active.keys {
                try Task.checkCancellation()
                try await stop(runnerID: id)
            }
        } catch {
            isQuitting = false
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
        guard let handle = runtime.handle else { return }
        guard runtime.phase != .stopping, stopChecks.insert(runnerID).inserted else {
            throw RunnerSupervisionError.operationInProgress
        }
        defer { stopChecks.remove(runnerID) }
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
        drainTimers.removeValue(forKey: id)?.cancel()
        monitors.removeValue(forKey: id)?.cancel()
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
