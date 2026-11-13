import CoreModels
import Foundation
import RunnerEngine
import SwiftData
import Testing
@testable import AppShellFeature

@MainActor
struct StorageMaintenanceTests {
    @Test("Manual mode never auto-cleans; opted-in age policy produces real counts and completion audit")
    func automaticPolicy() async throws {
        let fixture = try StorageFixture(now: .now)
        defer { fixture.remove() }
        let name = "storage-policy-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let controller = StorageMaintenanceController(preferences: preferences, cleaner: WorkspaceCleanerActor(baseRunnersDirectory: fixture.base), stateChecker: StorageAlwaysStoppedChecker())
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let model = RunnerEntity(id: fixture.runner.id, name: "fixture", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: fixture.root.appending(path: "_work"))
        container.mainContext.insert(model)
        await controller.refresh(in: container.mainContext)
        await controller.clean(in: container.mainContext, automatic: true)
        #expect(controller.lastReport == nil)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "_work/repo/data").path()))
        preferences.storagePolicy.pruningMode = .olderThanDays
        await controller.clean(in: container.mainContext, automatic: true)
        #expect(controller.lastReport?.removedCount == 2)
        #expect(!controller.failed && !controller.wasInterrupted && !controller.isBusy)
        let entries = try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(entries.contains { $0.title == "Storage cleanup" })
        model.isImportedLocal = true
        await controller.refresh(in: container.mainContext)
        #expect(controller.snapshot?.logicalBytesByCategory.isEmpty == true)
    }

    @Test("A missing runner root stops cleanup, clears the preview and records a failure audit")
    func missingRoot() async throws {
        let fixture = try StorageFixture(now: .now)
        defer { fixture.remove() }
        let name = "storage-missing-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let controller = StorageMaintenanceController(preferences: AppPreferencesStore(defaults: defaults), cleaner: WorkspaceCleanerActor(baseRunnersDirectory: fixture.base), stateChecker: StorageAlwaysStoppedChecker())
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        container.mainContext.insert(RunnerEntity(id: fixture.runner.id, name: "fixture", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: fixture.root.appending(path: "_work")))
        await controller.refresh(in: container.mainContext)
        try FileManager.default.removeItem(at: fixture.root)
        await controller.clean(in: container.mainContext)
        #expect(controller.failed && controller.snapshot == nil)
        let entries = try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(entries.contains { $0.title == "Storage cleanup failed" })
        await controller.refresh(in: container.mainContext)
        #expect(controller.failed && !controller.isBusy)
    }

    @Test("Interrupted cleanup leaves a durable attempt audit and invalidates its old preview")
    func interruptedCleanup() async throws {
        let now = Date.now
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let name = "storage-controller-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: fixture.base)
        let controller = StorageMaintenanceController(preferences: preferences, cleaner: cleaner, stateChecker: StorageCancelAfterRemovalChecker())
        #expect(controller.snapshot == nil)
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        container.mainContext.insert(RunnerEntity(id: fixture.runner.id, name: "fixture", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: fixture.root.appending(path: "_work")))
        try container.mainContext.save()
        await controller.refresh(in: container.mainContext)
        #expect(controller.snapshot?.candidates.count == 2)
        let operation = Task { await controller.clean(in: container.mainContext) }
        await operation.value
        #expect(controller.snapshot == nil)
        #expect(controller.wasInterrupted)
        let entries = try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(entries.contains { $0.title == "Storage cleanup started" })
        let remaining = ["_work/repo", "_diag/Runner_old.log"].filter { FileManager.default.fileExists(atPath: fixture.root.appending(path: $0).path()) }
        #expect(remaining.count == 1)
    }
}
private actor StorageCancelAfterRemovalChecker: StorageRunnerStateChecking {
    var calls = 0
    func isStopped(_ runner: ManagedStorageRunner) -> Bool {
        calls += 1
        if calls == 3 { withUnsafeCurrentTask { $0?.cancel() } }
        return true
    }
}

private actor StorageAlwaysStoppedChecker: StorageRunnerStateChecking {
    func isStopped(_ runner: ManagedStorageRunner) -> Bool { true }
}
