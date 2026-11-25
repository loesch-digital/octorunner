import AppShellFeature
import CoreModels
import Foundation
import SwiftData
import Testing

@MainActor
struct MonitoringConfigurationExporterTests {
    @Test func exportsRegisteredMetadataWithoutChangingRunnerOrFilesystem() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let root = "/Users/fixture/Documents/Example Runner"
        let work = URL(fileURLWithPath: root + "/_work")
        let scope = try #require(URL(string: "https://github.com/example/repository"))
        let runner = RunnerEntity(
            name: "Example",
            scopeUrl: scope,
            status: .busy,
            workDirectory: work,
            rootDirectoryPath: root + "/",
            isImportedLocal: true,
            pid: 123
        )
        context.insert(runner)
        try context.save()

        let snapshot = try MonitoringConfigurationExporter.configuration(in: context)
        #expect(snapshot.runners.map(\.id) == [runner.id])
        #expect(snapshot.runners.map(\.name) == ["Example"])
        #expect(snapshot.runners.map(\.processRootPath) == [root])
        let data = try JSONEncoder().encode(snapshot)
        let payload = String(decoding: data, as: UTF8.self)
        #expect(!payload.contains("_work"))
        #expect(!payload.contains("https:"))
        #expect(runner.rootDirectoryPath == root + "/")
        #expect(runner.status == .busy)
        #expect(runner.pid == 123)
        #expect(!context.hasChanges)
    }

    @Test func revisionChangesForRegistrationUpdatesAndIgnoresRuntimeState() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let runner = RunnerEntity(
            name: "Initial",
            scopeUrl: try #require(URL(string: "https://github.com/example/repository")),
            workDirectory: URL(fileURLWithPath: "/example/runner/_work")
        )
        context.insert(runner)
        try context.save()
        let initial = try MonitoringConfigurationExporter.configuration(in: context)
        runner.status = .offline
        try context.save()
        #expect(try MonitoringConfigurationExporter.configuration(in: context, previous: initial) == initial)
        runner.name = "Renamed"
        try context.save()
        let updated = try MonitoringConfigurationExporter.configuration(in: context, previous: initial)
        #expect(updated.revision != initial.revision)
        #expect(updated.runners.map(\.name) == ["Renamed"])
    }
}
