import AppShellFeature
import CoreModels
import Foundation
import GitHubAPI
import RunnerEngine
import SwiftData
import Testing

@MainActor
struct RunnerWizardProvisioningTests {
    @Test("Wizard preserves launch settings and form values across token loading")
    func launchSnapshot() async throws {
        let gate = WizardGate()
        let client = WizardTargetClient(gate: gate)
        let engine = WizardProvisioner()
        let vm = AddRunnerWizardViewModel(provisioningClient: client, provisionerActor: engine)
        vm.manualTargetInput = "owner/repository"
        vm.baseNamePrefix = "original"
        vm.instanceCount = 1
        vm.selectedLabels = ["self-hosted", "original"]
        var policy = RunnerRuntimePolicy()
        policy.shell = .zsh
        policy.restartPolicy = .manual
        let configuration = RunnerLaunchConfiguration(runtimePolicy: policy, inheritHostPath: false, hostPath: "/ignored")
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let task = Task { await vm.provisionAndPersistRunners(accountLogin: "fixture", modelContext: context, configuration: configuration) }
        await gate.waitUntilEntered()
        vm.baseNamePrefix = "changed"
        vm.selectedScope = .organization
        vm.selectedLabels = ["changed"]
        await gate.release()
        #expect(await task.value)
        let request = try #require(await engine.request)
        #expect(request.names == ["original-1"])
        #expect(request.scope == .repository)
        #expect(request.labels == ["self-hosted", "original"])
        #expect(request.configuration.environment["SHELL"] == "/bin/zsh")
        #expect(request.configuration.runtimePolicy.restartPolicy == .manual)
        let saved = try #require(context.fetch(FetchDescriptor<RunnerEntity>()).first)
        #expect(saved.rootDirectoryPath == "/tmp/runner fixture")
    }

    @Test("Cancelled provisioning does not insert late runner results or start a duplicate request")
    func cancellationAndReentry() async throws {
        let gate = WizardGate()
        let engine = WizardProvisioner(gate: gate)
        let vm = AddRunnerWizardViewModel(provisioningClient: WizardTargetClient(), provisionerActor: engine)
        vm.manualTargetInput = "owner/repository"
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let task = Task { await vm.provisionAndPersistRunners(accountLogin: "fixture", modelContext: context) }
        await gate.waitUntilEntered()
        #expect(!((await vm.provisionAndPersistRunners(accountLogin: "fixture", modelContext: context))))
        task.cancel()
        await gate.release()
        #expect(!(await task.value))
        #expect(try context.fetchCount(FetchDescriptor<RunnerEntity>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
        #expect(vm.errorMessage == nil)
        #expect(!vm.isProvisioning)
        #expect(await engine.calls == 1)
    }
}

private actor WizardGate {
    private let entered = AsyncStream<Void>.makeStream()
    private let released = AsyncStream<Void>.makeStream()
    func enter() async {
        entered.continuation.yield(())
        entered.continuation.finish()
        for await _ in released.stream { break }
    }
    func waitUntilEntered() async { for await _ in entered.stream { break } }
    func release() { released.continuation.yield(()); released.continuation.finish() }
}

private actor WizardTargetClient: RunnerTargetLoading {
    let gate: WizardGate?
    init(gate: WizardGate? = nil) { self.gate = gate }
    func readToken(for accountLogin: String) async throws -> String {
        if let gate { await gate.enter() }
        return "test-only-credential"
    }
    func fetchUserRepositories(token: String) async throws -> [GitHubRepositorySummaryDTO] { [] }
    func fetchUserOrganizations(token: String) async throws -> [GitHubOrganizationSummaryDTO] { [] }
}

private actor WizardProvisioner: RunnerProvisioning {
    struct Request: Sendable {
        let names: [String]
        let scope: RunnerScopeType
        let labels: [String]
        let configuration: RunnerLaunchConfiguration
    }
    let gate: WizardGate?
    private(set) var request: Request?
    private(set) var calls = 0
    init(gate: WizardGate? = nil) { self.gate = gate }
    func provisionRunners(instanceNames: [String], scopeType: RunnerScopeType, scopeURL: URL, labels: [String], registerLaunchAgent: Bool, accessToken: String, configuration: RunnerLaunchConfiguration, onStatusUpdate: @MainActor @Sendable (String) -> Void) async throws -> [ProvisionedRunnerSummary] {
        calls += 1
        request = Request(names: instanceNames, scope: scopeType, labels: labels, configuration: configuration)
        if calls == 1, let gate { await gate.enter() }
        return [ProvisionedRunnerSummary(name: instanceNames[0], scopeType: scopeType, scopeURL: scopeURL, rootDirectory: URL(fileURLWithPath: "/tmp/runner fixture"), workDirectory: URL(fileURLWithPath: "/tmp/runner fixture/_work"), labels: labels, runnerVersion: "fixture", launchdLabel: nil, pid: nil)]
    }
}
