@testable import AppShellFeature
import CoreModels
import Foundation
import SwiftData
import SyncKit
import Testing

@MainActor
struct FilesystemModelPathTests {
    @Test("A discovered runner with the same name and numeric ID in another repository keeps its own row")
    func separatesRepositoryIdentities() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let firstScope = try #require(URL(string: "https://github.com/example/first"))
        let secondScope = try #require(URL(string: "https://github.com/example/second"))
        let firstRoot = URL(filePath: "/tmp/runner-sync-first")
        let secondRoot = URL(filePath: "/tmp/runner-sync-second")
        let first = RunnerEntity(name: "same-name", scopeUrl: firstScope, labels: ["custom-label"],
                                 workDirectory: firstRoot.appending(path: "_work"), isImportedLocal: true)
        first.githubRunnerId = 21
        context.insert(first)
        try context.save()
        let other = DiscoveredLocalRunner(rootDirectory: secondRoot,
            config: .init(agentId: 21, agentName: first.name, gitHubUrl: secondScope),
            workDirectory: secondRoot.appending(path: "_work"), runnerVersion: nil, listenerPID: nil,
            isWorkerActive: false)

        LocalRunnerImportStore.upsert([other], into: context)

        #expect(try context.fetchCount(FetchDescriptor<RunnerEntity>()) == 2)
        #expect(first.scopeUrlString == firstScope.absoluteString)
        #expect(first.labels == ["custom-label"])
    }

    private static var retainedContainers: [ModelContainer] = []

    @Test("Discovery never reassigns an owned runner to another folder", arguments: [RunnerExecutionMode.direct, .launchAgent])
    func discoveryPreservesOwnedRoot(mode: RunnerExecutionMode) throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let expectedRoot = URL(filePath: "/tmp/managed/runner")
        let otherRoot = URL(filePath: "/tmp/other/runner")
        let scope = try #require(URL(string: "https://github.com/example/repo"))
        let runner = RunnerEntity(name: "Runner", scopeUrl: scope,
            workDirectory: expectedRoot.appending(path: "_work"), rootDirectoryPath: expectedRoot.path, executionMode: mode)
        runner.githubRunnerId = 42
        context.insert(runner)
        try context.save()
        let discovered = DiscoveredLocalRunner(rootDirectory: otherRoot,
            config: .init(agentId: 42, agentName: runner.name, gitHubUrl: scope),
            workDirectory: otherRoot.appending(path: "_work"), runnerVersion: nil, listenerPID: 123, isWorkerActive: false)

        LocalRunnerImportStore.upsert([discovered], into: context)
        let rows = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(runner.executionMode == mode)
        #expect(runner.rootDirectoryPath == expectedRoot.path)
        #expect(runner.pid == nil)
        #expect(rows.contains { $0.executionMode == .external && $0.rootDirectoryPath == otherRoot.path })
    }

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
        LocalRunnerImportStore.upsert([discovered], into: container.mainContext)
        let runner = try #require(container.mainContext.fetch(FetchDescriptor<RunnerEntity>()).first)
        #expect(runner.rootDirectoryPath == root)
        #expect(runner.workDirectoryPath == root + "/_work")
        runner.rootDirectoryPath = "/tmp/100%2520literal/Runner%20Fleet"
        runner.workDirectoryPath = "/tmp/100%2520literal/Runner%20Fleet/_work"
        LocalRunnerImportStore.upsert([discovered], into: container.mainContext)
        #expect(runner.rootDirectoryPath == root)
        #expect(runner.workDirectoryPath == root + "/_work")
        #expect(try container.mainContext.fetchCount(FetchDescriptor<RunnerEntity>()) == 1)
    }

    @Test("Repeated discovery updates the same runner and preserves its identity")
    func upsertDiscoveredRunnersIdempotency() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let context = container.mainContext

        let discovered = DiscoveredLocalRunner(
            rootDirectory: URL(fileURLWithPath: "/tmp/example-actions-runner"),
            config: LocalDotRunnerConfig(
                agentId: 21,
                agentName: "example-local-runner",
                gitHubUrl: try #require(URL(string: "https://github.com/example/project")),
                workFolder: "_work"
            ),
            workDirectory: URL(fileURLWithPath: "/tmp/example-actions-runner/_work"),
            runnerVersion: "2.338.2",
            listenerPID: 87558,
            isWorkerActive: false,
            labels: ["self-hosted", "macOS", "ARM64"]
        )

        // First sync imports the runner
        let importedCount = LocalRunnerImportStore.upsert([discovered], into: context)
        #expect(importedCount == 1)

        var allRunners = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(allRunners.count == 1)
        #expect(allRunners.first?.name == "example-local-runner")
        #expect(allRunners.first?.githubRunnerId == 21)
        #expect(allRunners.first?.pid == 87558)
        #expect(allRunners.first?.status == .idle)

        // Second sync updates in-place (no duplicate created)
        var busyDiscovered = discovered
        busyDiscovered.localStatus = .busy
        let secondCount = LocalRunnerImportStore.upsert([busyDiscovered], into: context)
        #expect(secondCount == 1)

        allRunners = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(allRunners.count == 1)
        #expect(allRunners.first?.status == .busy)
    }
}
