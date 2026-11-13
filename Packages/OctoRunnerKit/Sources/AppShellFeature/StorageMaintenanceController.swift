import CoreModels
import Foundation
import Observation
import RunnerEngine
import SwiftData
import TelemetryKit

@MainActor
@Observable
public final class StorageMaintenanceController {
    public private(set) var snapshot: StorageUsageSnapshot?
    public private(set) var volume: VolumeCapacitySnapshot?
    public private(set) var lastReport: StorageCleanupReport?
    public private(set) var isBusy = false
    public private(set) var failed = false
    public private(set) var wasInterrupted = false
    @ObservationIgnored private let preferences: AppPreferencesStore
    @ObservationIgnored private let cleaner: WorkspaceCleanerActor
    @ObservationIgnored private let stateChecker: (any StorageRunnerStateChecking)?
    @ObservationIgnored private let capacity = SystemVolumeCapacitySampler()
    @ObservationIgnored private var task: Task<Void, Never>?

    public init(preferences: AppPreferencesStore, cleaner: WorkspaceCleanerActor = WorkspaceCleanerActor(), stateChecker: (any StorageRunnerStateChecking)? = nil) {
        self.preferences = preferences; self.cleaner = cleaner
        self.stateChecker = stateChecker
    }

    isolated deinit { task?.cancel() }

    public func start(container: ModelContainer) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.preferences.storagePolicy.pruningMode != .manual {
                    await self.refresh(in: container.mainContext)
                    guard !Task.isCancelled else { return }
                    await self.clean(in: container.mainContext, automatic: true)
                }
                do { try await Task.sleep(for: .seconds(600)) } catch { return }
            }
        }
    }

    public func stop() { task?.cancel(); task = nil }

    public func refresh(in context: ModelContext) async {
        guard !Task.isCancelled, !isBusy else { return }
        isBusy = true; failed = false
        defer { isBusy = false }
        do {
            let runners = try managedRunners(in: context)
            let result = try await cleaner.inspect(runners: runners, workspaceAgeDays: preferences.pruneWorkspacesOlderThanDays,
                logRetentionDays: preferences.storagePolicy.logRetentionDays)
            guard !Task.isCancelled else { return }
            let volume = await capacity.sample()
            guard !Task.isCancelled else { return }
            self.volume = volume; snapshot = result
        } catch is CancellationError { return }
        catch { if !Task.isCancelled { failed = true; snapshot = nil } }
    }

    public func clean(in context: ModelContext, automatic: Bool = false, candidateSnapshot: StorageUsageSnapshot? = nil) async {
        guard !Task.isCancelled, !isBusy, let snapshot = candidateSnapshot ?? snapshot else { return }
        let policy = preferences.storagePolicy
        let workspaceAge = preferences.pruneWorkspacesOlderThanDays
        guard !automatic || policy.pruningMode != .manual else { return }
        let threshold = automatic && policy.pruningMode == .lowDiskSpace ? Int64(policy.minimumFreeSpaceGB) * 1_000_000_000 : nil
        isBusy = true; failed = false; wasInterrupted = false; lastReport = nil
        self.snapshot = nil; volume = nil
        defer { isBusy = false }
        do {
            let roots = try managedRunners(in: context)
            if !snapshot.candidates.isEmpty {
                // Persist intent before any deletion. Cancellation may prevent a
                // completion record, and must never access models after teardown.
                context.insert(AuditLogEntity(category: .system, title: "Storage cleanup started", summary: "Reviewing \(snapshot.candidates.count) old managed items. An interrupted attempt may be partial; only a completion entry confirms the final counts."))
                try context.save()
            }
            let gate = ManagedStorageRunnerGate(context: context, isAuthorized: { [preferences] in
                preferences.storagePolicy == policy && preferences.pruneWorkspacesOlderThanDays == workspaceAge
            })
            let report = try await cleaner.clean(snapshot.candidates, runners: roots, checker: stateChecker ?? gate,
                workspaceAgeDays: workspaceAge, logRetentionDays: policy.logRetentionDays, stopWhenAvailableBytes: threshold)
            guard !Task.isCancelled else { wasInterrupted = true; return }
            lastReport = report
            if !snapshot.candidates.isEmpty {
                context.insert(AuditLogEntity(category: .system, title: "Storage cleanup", summary: "Removed \(report.removedCount) old managed items (\(report.removedLogicalBytes) logical bytes); skipped \(report.skippedCount)."))
                try context.save()
            }
            self.snapshot = nil
            volume = nil
        } catch is CancellationError { wasInterrupted = true; return }
        catch {
            guard !Task.isCancelled else { wasInterrupted = true; return }
            failed = true
            context.insert(AuditLogEntity(category: .system, severity: .warning, title: "Storage cleanup failed", summary: "Cleanup stopped; earlier items may already have been removed. No further items were processed."))
            try? context.save()
        }
    }

    private func managedRunners(in context: ModelContext) throws -> [ManagedStorageRunner] {
        try context.fetch(FetchDescriptor<RunnerEntity>()).compactMap { model in
            guard !model.isImportedLocal, let path = model.rootDirectoryPath else { return nil }
            let root = URL(fileURLWithPath: path)
            let parent = root.deletingLastPathComponent().pathComponents
            guard parent == cleaner.baseRunnersDirectory.pathComponents else { return nil }
            return ManagedStorageRunner(id: model.id, root: root, serviceLabel: model.serviceLabel)
        }
    }
}
