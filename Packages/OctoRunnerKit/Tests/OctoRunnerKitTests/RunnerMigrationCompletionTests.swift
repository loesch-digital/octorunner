import CoreModels
import Foundation
@testable import AppShellFeature
@testable import RunnerEngine
import SwiftData
import SyncKit
import Testing

@MainActor
struct RunnerMigrationCompletionTests {
    @Test("Migration of an older organization runner saves its verified group with the new registration ID")
    func recordsVerifiedGroup() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let source = URL(filePath: "/tmp/imported org runner")
        let runner = RunnerEntity(name: "Org Fixture", scopeType: .organization,
            scopeUrl: URL(string: "https://github.com/example")!, workDirectory: source, isImportedLocal: true)
        runner.rootDirectoryPath = source.path
        runner.githubRunnerId = 21
        context.insert(runner)
        try context.save()

        #expect(try RunnerMigrationCompletion.apply(
            runnerID: runner.id, expectedSourcePath: source.path, managedRoot: URL(filePath: "/tmp/managed org runner"),
            context: context, actorLogin: nil, oldRemoteID: 21, newRemoteID: 37,
            installedVersion: "fixture", verifiedGroup: RunnerMigrationGroup(id: 5, name: "Mac Builds")
        ) == "Org Fixture")
        let persisted = try #require(ModelContext(container).fetch(FetchDescriptor<RunnerEntity>()).first)
        #expect(persisted.githubRunnerId == 37)
        #expect(persisted.githubRunnerGroupID == 5)
        #expect(persisted.githubRunnerGroupName == "Mac Builds")
    }

    @Test("Migration completion refetches the expected imported runner before writing")
    func completionUsesCurrentIdentity() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let source = "/tmp/imported runner %20"
        let runner = RunnerEntity(name: "Build Fixture", scopeUrl: URL(string: "https://github.com/owner/repo")!, workDirectory: URL(fileURLWithPath: source), isImportedLocal: true)
        runner.rootDirectoryPath = source + "/"
        runner.githubRunnerId = 21
        context.insert(runner)
        try context.save()
        let root = URL(filePath: "/tmp/managed runner %20", directoryHint: .isDirectory)
        #expect(try RunnerMigrationCompletion.apply(runnerID: runner.id, expectedSourcePath: source + "changed", managedRoot: root, context: context, actorLogin: nil) == nil)
        #expect(runner.isImportedLocal)
        #expect(try RunnerMigrationCompletion.apply(runnerID: runner.id, expectedSourcePath: source, managedRoot: root, context: context, actorLogin: nil,
            oldRemoteID: 20, newRemoteID: 37, installedVersion: "2.340.0") == nil)
        #expect(runner.githubRunnerId == 21)
        #expect(try RunnerMigrationCompletion.apply(runnerID: runner.id, expectedSourcePath: source, managedRoot: root, context: context, actorLogin: nil,
            oldRemoteID: 21, newRemoteID: 37, installedVersion: "2.340.0") == "Build Fixture")
        #expect(!runner.isImportedLocal)
        #expect(runner.githubRunnerId == 37)
        #expect(runner.runnerVersion == "2.340.0")
        #expect(runner.serviceLabel == "io.octorunner.agent.build-fixture")
        #expect(runner.executionMode == .launchAgent)
        #expect(runner.rootDirectoryPath == "/tmp/managed runner %20")
        #expect(runner.workDirectoryPath == "/tmp/managed runner %20/_work")
        let count = try context.fetchCount(FetchDescriptor<AuditLogEntity>())
        #expect(count == 1)
        let audit = try #require(context.fetch(FetchDescriptor<AuditLogEntity>()).first)
        #expect(audit.targetRunnerName == "Build Fixture")
        #expect(try RunnerMigrationCompletion.apply(runnerID: runner.id, expectedSourcePath: source, managedRoot: root, context: context, actorLogin: nil) == nil)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == count)
        let original = DiscoveredLocalRunner(rootDirectory: URL(filePath: source),
            config: .init(agentId: 21, agentName: runner.name, gitHubUrl: URL(string: runner.scopeUrlString)!),
            workDirectory: URL(filePath: source).appending(path: "_work"), runnerVersion: nil, listenerPID: nil,
            isWorkerActive: false)
        #expect(LocalRunnerImportStore.upsert([original], into: context) == 0)
        #expect(try context.fetchCount(FetchDescriptor<RunnerEntity>()) == 1)
        let id = runner.id
        context.delete(runner)
        try context.save()
        #expect(try RunnerMigrationCompletion.apply(runnerID: id, expectedSourcePath: source, managedRoot: root, context: context, actorLogin: nil) == nil)
    }

    @Test("Cancelled migration completion performs no model mutation or audit write")
    func cancellationPreventsPersistence() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let runner = RunnerEntity(name: "fixture", scopeUrl: URL(string: "https://github.com/owner/repo")!, workDirectory: URL(fileURLWithPath: "/tmp/source"), isImportedLocal: true)
        context.insert(runner)
        try context.save()
        let id = runner.id
        let cancelled = await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try RunnerMigrationCompletion.apply(runnerID: id, expectedSourcePath: "/tmp/source", managedRoot: URL(fileURLWithPath: "/tmp/destination"), context: context, actorLogin: nil)
                return false
            } catch is CancellationError { return true }
            catch { return false }
        }.value
        #expect(cancelled)
        #expect(runner.isImportedLocal)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
    }
}
