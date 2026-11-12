import AppShellFeature
import CoreModels
import Foundation
import SwiftData
import SyncKit
import Testing

@MainActor
struct FilesystemModelPathTests {
    private static var retainedContainers: [ModelContainer] = []

    @Test("Runner models store filesystem paths with spaces and literal percent sequences")
    func modelPaths() throws {
        let work = "/tmp/100%20literal/Runner Fleet/_work"
        let runner = RunnerEntity(name: "Runner", scopeUrl: try #require(URL(string: "https://github.com/example/repo")),
            workDirectory: URL(fileURLWithPath: work))
        #expect(runner.workDirectoryPath == work)
        #expect(runner.rootDirectoryPath == "/tmp/100%20literal/Runner Fleet/")
    }

    @Test("Discovery import and update repair stored encoded paths without decoding literal percent names")
    func importedPaths() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let root = "/tmp/100%20literal/Runner Fleet"
        let discovered = DiscoveredLocalRunner(rootDirectory: URL(fileURLWithPath: root),
            config: LocalDotRunnerConfig(agentId: 42, agentName: "Runner", gitHubUrl: try #require(URL(string: "https://github.com/example/repo")), workFolder: "_work"),
            workDirectory: URL(fileURLWithPath: root + "/_work"), runnerVersion: nil, listenerPID: nil, isWorkerActive: false)
        MainShellView.upsertDiscoveredRunners([discovered], into: container.mainContext)
        let runner = try #require(container.mainContext.fetch(FetchDescriptor<RunnerEntity>()).first)
        #expect(runner.rootDirectoryPath == root)
        #expect(runner.workDirectoryPath == root + "/_work")
        runner.rootDirectoryPath = "/tmp/100%2520literal/Runner%20Fleet"
        runner.workDirectoryPath = "/tmp/100%2520literal/Runner%20Fleet/_work"
        MainShellView.upsertDiscoveredRunners([discovered], into: container.mainContext)
        #expect(runner.rootDirectoryPath == root)
        #expect(runner.workDirectoryPath == root + "/_work")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RunnerEntity>()) == 1)
    }
}
