import CoreModels
import Foundation
import Observation
import SwiftData
import SyncKit

/// App-lifetime local process monitoring. Closing a window does not stop it;
/// quitting the app does. No runner folder is opened by this service.
@MainActor
@Observable
public final class RunnerHealthMonitor {
    public private(set) var observations: [RunnerHealthObservation] = []
    @ObservationIgnored private let notifications: AppNotificationsController
    @ObservationIgnored private let sampler: any RunnerProcessSampling
    @ObservationIgnored private let preferences: AppPreferencesStore?
    @ObservationIgnored private var tracker = RunnerHealthTransitionTracker()
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var generation = 0

    public init(notifications: AppNotificationsController, sampler: any RunnerProcessSampling = RunnerProcessSampler(), preferences: AppPreferencesStore? = nil) {
        self.notifications = notifications
        self.sampler = sampler
        self.preferences = preferences
    }

    public func health(at date: Date) -> RunnerFleetHealth {
        RunnerFleetHealth.summarize(observations, at: date)
    }

    public func start(container: ModelContainer) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh(in: container.mainContext)
                do { try await Task.sleep(for: .seconds(15)) }
                catch { return }
            }
        }
    }

    public func stop() {
        generation += 1
        task?.cancel()
        task = nil
    }

    public func refresh(in context: ModelContext) async {
        guard !Task.isCancelled, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let revision = generation
        do {
            let presence = try await sampler.sample()
            guard !Task.isCancelled, revision == generation else { return }
            // Fetch after suspension: removed runners are never retained across await.
            let runners = try context.fetch(FetchDescriptor<RunnerEntity>())
            let now = Date.now
            observations = runners.map { runner in
                guard let path = runner.rootDirectoryPath, path.hasPrefix("/") else {
                    return RunnerHealthObservation(id: runner.id, name: runner.name, status: nil, observedAt: now)
                }
                let root = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(fileURLWithPath: path))
                let process = presence[root]
                let status: RunnerStatus
                if process?.isWorkerActive == true { status = .busy }
                else if process?.listenerPID != nil { status = .idle }
                else { status = runner.status == .faulted ? .faulted : .offline }
                runner.status = status
                runner.pid = process?.listenerPID ?? process?.workerPID
                runner.lastHeartbeat = now
                return RunnerHealthObservation(id: runner.id, name: runner.name, status: status, observedAt: now)
            }
            try context.save()
            let events = tracker.consume(observations, at: now, locale: preferences?.language.locale ?? .current)
            for event in events {
                guard !Task.isCancelled, revision == generation else { return }
                AuditLogRecorder.record(in: context, category: .runnerLifecycle,
                    severity: event.kind == .runnerError ? .critical : event.kind == .runnerOffline ? .warning : .info,
                    title: event.title, summary: "Local process state changed; this is not a workflow job result.",
                    targetRunnerName: event.message)
                await notifications.publish(event)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, revision == generation else { return }
            // Unavailable data is not evidence of an outage. Reset the transition
            // baseline so recovery from a measurement failure sends no false alert.
            observations = []
            _ = tracker.consume([], at: .now)
        }
    }
}
