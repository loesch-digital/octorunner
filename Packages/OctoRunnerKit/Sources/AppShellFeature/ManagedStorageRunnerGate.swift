import CoreModels
import Foundation
import RunnerEngine
import SwiftData
import SyncKit

@MainActor
final class ManagedStorageRunnerGate: StorageRunnerStateChecking {
    private let context: ModelContext
    private let sampler: any RunnerProcessSampling
    private let services: any RunnerServiceStateReading
    private let isAuthorized: @MainActor @Sendable () -> Bool

    init(context: ModelContext, sampler: any RunnerProcessSampling = RunnerProcessSampler(), services: any RunnerServiceStateReading = RunnerSupervisorActor(), isAuthorized: @escaping @MainActor @Sendable () -> Bool = { true }) {
        self.context = context; self.sampler = sampler; self.services = services
        self.isAuthorized = isAuthorized
    }

    func isStopped(_ runner: ManagedStorageRunner) async throws -> Bool {
        guard !Task.isCancelled, isCurrent(runner) else { return false }
        let processes = try await sampler.sample()
        guard !Task.isCancelled, isCurrent(runner) else { return false }
        let path = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: runner.root)
        guard processes[path]?.listenerPID == nil, processes[path]?.workerPID == nil else { return false }
        let unloaded = try await services.isUnloaded(label: runner.serviceLabel)
        guard !Task.isCancelled else { return false }
        return unloaded && isCurrent(runner)
    }

    private func isCurrent(_ runner: ManagedStorageRunner) -> Bool {
        guard isAuthorized() else { return false }
        let id = runner.id
        guard let matches = try? context.fetch(FetchDescriptor<RunnerEntity>(predicate: #Predicate { $0.id == id })),
              matches.count == 1, let model = matches.first, !model.isImportedLocal,
              let path = model.rootDirectoryPath,
              LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(fileURLWithPath: path)) == LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: runner.root),
              model.serviceLabel == runner.serviceLabel,
              model.serviceLabel == RunnerServiceLabel.forRunner(named: model.name) else { return false }
        return true
    }
}
