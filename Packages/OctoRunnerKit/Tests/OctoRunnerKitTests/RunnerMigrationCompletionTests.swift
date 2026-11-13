import CoreModels
import Foundation
@testable import AppShellFeature
import SwiftData
import Testing

@MainActor
struct RunnerMigrationCompletionTests {
    @Test("Migration completion refetches the expected imported runner before writing")
    func completionUsesCurrentIdentity() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let source = "/tmp/imported runner %20"
        let runner = RunnerEntity(name: "fixture", scopeUrl: URL(string: "https://github.com/owner/repo")!, workDirectory: URL(fileURLWithPath: source), isImportedLocal: true)
        runner.rootDirectoryPath = source
        context.insert(runner)
        try context.save()
        let root = URL(fileURLWithPath: "/tmp/managed runner %20")
        #expect(try RunnerMigrationCompletion.apply(runnerID: runner.id, expectedSourcePath: source + "changed", managedRoot: root, context: context, actorLogin: nil) == nil)
        #expect(runner.isImportedLocal)
        #expect(try RunnerMigrationCompletion.apply(runnerID: runner.id, expectedSourcePath: source, managedRoot: root, context: context, actorLogin: nil) == "fixture")
        #expect(!runner.isImportedLocal)
        #expect(runner.rootDirectoryPath == "/tmp/managed runner %20")
        #expect(runner.workDirectoryPath == "/tmp/managed runner %20/_work")
        let count = try context.fetchCount(FetchDescriptor<AuditLogEntity>())
        #expect(count == 1)
        #expect(try RunnerMigrationCompletion.apply(runnerID: runner.id, expectedSourcePath: source, managedRoot: root, context: context, actorLogin: nil) == nil)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == count)
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
