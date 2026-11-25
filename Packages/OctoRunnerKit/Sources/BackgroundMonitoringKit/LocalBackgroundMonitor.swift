import CoreModels
import Foundation
import SyncKit

public struct LocalBackgroundMonitor: Sendable {
    private let store: MonitoringSnapshotStore
    private let sampler: any RunnerProcessSampling

    public init(store: MonitoringSnapshotStore, sampler: any RunnerProcessSampling = RunnerProcessSampler()) {
        self.store = store
        self.sampler = sampler
    }

    /// Call from the process holding the monitoring lease.
    public func refresh(at measurementTime: Date? = nil) async throws {
        try Task.checkCancellation()
        guard let configuration = try store.readConfiguration() else { return }

        let statuses: [UUID: RunnerStatus]
        do {
            let processes = try await sampler.sample()
            statuses = Self.statuses(for: configuration.runners, in: processes)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            statuses = [:]
        }

        try Task.checkCancellation()
        guard try store.readConfiguration()?.revision == configuration.revision else { return }
        try store.writeObservation(MonitoringObservation(
            configurationRevision: configuration.revision,
            observedAt: measurementTime ?? .now,
            statuses: statuses
        ))
    }

    private static func statuses(
        for runners: [MonitoringRunnerDescriptor],
        in processes: [String: RunnerProcessPresence]
    ) -> [UUID: RunnerStatus] {
        var observed: [UUID: RunnerStatus] = [:]
        for runner in runners {
            guard let path = runner.processRootPath, path.hasPrefix("/") else { continue }
            let presence = processes[path]
            if presence?.isWorkerActive == true {
                observed[runner.id] = .busy
            } else if presence?.listenerPID != nil {
                observed[runner.id] = .idle
            } else {
                observed[runner.id] = .offline
            }
        }
        return observed
    }
}
