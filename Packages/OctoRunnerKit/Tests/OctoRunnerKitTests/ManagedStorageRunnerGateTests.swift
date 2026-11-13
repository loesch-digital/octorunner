import Foundation
import CoreModels
import RunnerEngine
import SwiftData
import SyncKit
import Testing
@testable import AppShellFeature

@MainActor
struct ManagedStorageRunnerGateTests {
    @Test("Cleanup requires an unloaded service and absence of both listener and worker")
    func stoppedState() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let root = URL(fileURLWithPath: "/tmp/storage-gate-fixture")
        let model = RunnerEntity(name: "fixture", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: root.appending(path: "_work"))
        container.mainContext.insert(model)
        let runner = ManagedStorageRunner(id: model.id, root: root, serviceLabel: model.serviceLabel)
        for presence in [RunnerProcessPresence(listenerPID: 12), RunnerProcessPresence(workerPID: 13)] {
            let gate = ManagedStorageRunnerGate(context: container.mainContext, sampler: StorageProcessFixture(values: [root.path(): presence]), services: StorageServiceFixture(unloaded: true))
            #expect(try await !gate.isStopped(runner))
        }
        for unloaded in [false, true] {
            let gate = ManagedStorageRunnerGate(context: container.mainContext, sampler: StorageProcessFixture(values: [:]), services: StorageServiceFixture(unloaded: unloaded))
            #expect(try await gate.isStopped(runner) == unloaded)
        }
    }

    @Test("Cleanup verifies the canonical provisioned service label, including normalized names")
    func canonicalLabel() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let root = URL(fileURLWithPath: "/tmp/storage-gate-fixture")
        let model = RunnerEntity(name: "Mac Runner", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: root.appending(path: "_work"))
        container.mainContext.insert(model)
        let gate = ManagedStorageRunnerGate(context: container.mainContext, sampler: StorageProcessFixture(values: [:]), services: StorageServiceFixture(unloaded: true))
        let legacy = ManagedStorageRunner(id: model.id, root: root, serviceLabel: model.serviceLabel)
        #expect(try await !gate.isStopped(legacy))
        model.serviceLabel = "io.octorunner.agent.mac-runner"
        let provisioned = ManagedStorageRunner(id: model.id, root: root, serviceLabel: model.serviceLabel)
        #expect(try await gate.isStopped(provisioned))
    }

    @Test("Revoked cleanup authorization prevents filesystem state checks")
    func revoked() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let root = URL(fileURLWithPath: "/tmp/storage-gate-fixture")
        let model = RunnerEntity(name: "fixture", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: root.appending(path: "_work"))
        container.mainContext.insert(model)
        let runner = ManagedStorageRunner(id: model.id, root: root, serviceLabel: model.serviceLabel)
        let gate = ManagedStorageRunnerGate(context: container.mainContext, sampler: StorageProcessFixture(values: [:]), services: StorageServiceFixture(unloaded: true), isAuthorized: { false })
        #expect(try await !gate.isStopped(runner))
    }
}

private actor StorageProcessFixture: RunnerProcessSampling {
    let values: [String: RunnerProcessPresence]
    init(values: [String: RunnerProcessPresence]) { self.values = values }
    func sample() -> [String: RunnerProcessPresence] { values }
}
private actor StorageServiceFixture: RunnerServiceStateReading {
    let unloaded: Bool
    init(unloaded: Bool) { self.unloaded = unloaded }
    func isUnloaded(label: String) -> Bool { unloaded }
}
