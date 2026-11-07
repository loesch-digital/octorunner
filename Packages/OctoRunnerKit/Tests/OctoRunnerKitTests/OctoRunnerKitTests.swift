import CoreModels
import Foundation
import GitHubAPI
import SecurityKit
import SwiftData
import TelemetryKit
import Testing

@Suite("OctoRunnerKit Core Infrastructure Tests")
struct OctoRunnerKitTests {
    @Test("In-memory SwiftData RunnerEntity creation and cascade delete relationship")
    @MainActor
    func runnerEntityPersistenceAndCascadeDelete() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RunnerEntity.self, JobRunEntity.self, configurations: config)
        let context = container.mainContext

        let runner = RunnerEntity(
            name: "mac-runner-test",
            scopeType: .repository,
            scopeUrl: URL(string: "https://github.com/loesch-digital/octorunner")!,
            status: .idle,
            labels: ["self-hosted", "macos", "arm64"],
            workDirectory: URL(fileURLWithPath: "/tmp/octorunner-test")
        )
        let job = JobRunEntity(
            githubRunId: 10842,
            workflowName: "CI / macOS Build",
            repositoryFullName: "loesch-digital/octorunner",
            branchName: "main",
            commitSha: "b93dfa1",
            statusRaw: "completed",
            durationSeconds: 42.5,
            runner: runner
        )
        context.insert(runner)
        context.insert(job)
        try context.save()

        let fetchedRunners = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(fetchedRunners.count == 1)
        #expect(fetchedRunners.first?.name == "mac-runner-test")
        #expect(fetchedRunners.first?.status == .idle)
        #expect(fetchedRunners.first?.jobRuns.count == 1)
        #expect(fetchedRunners.first?.serviceLabel == "io.octorunner.agent.mac-runner-test")

        // Verify cascade delete removes associated JobRunEntity
        context.delete(runner)
        try context.save()
        let remainingJobs = try context.fetch(FetchDescriptor<JobRunEntity>())
        #expect(remainingJobs.isEmpty)
    }

    @Test("KeychainVaultActor add-or-update, read, and delete lifecycle")
    func keychainAddUpdateAndDeleteLifecycle() async throws {
        let vault = KeychainVaultActor(servicePrefix: "io.octorunner.macos.tests.\(UUID().uuidString)")
        let account = "test-user"

        // Initially nil
        let initial = try await vault.readSecret(account: account)
        #expect(initial == nil)

        // Add secret
        try await vault.saveSecret("gho_initial_token_123", account: account)
        let saved = try await vault.readSecret(account: account)
        #expect(saved == "gho_initial_token_123")

        // Update existing secret (tests errSecDuplicateItem -> SecItemUpdate path)
        try await vault.saveSecret("gho_updated_token_456", account: account)
        let updated = try await vault.readSecret(account: account)
        #expect(updated == "gho_updated_token_456")

        // Delete secret
        try await vault.deleteSecret(account: account)
        let afterDelete = try await vault.readSecret(account: account)
        #expect(afterDelete == nil)
    }

    @Test("GitHubRunnerDownloadDTO decodes snake_case GitHub REST API JSON")
    func runnerDownloadDTODecoding() throws {
        let json = """
        {
          "os": "osx",
          "architecture": "arm64",
          "download_url": "https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-osx-arm64-2.338.2.tar.gz",
          "filename": "actions-runner-osx-arm64-2.338.2.tar.gz",
          "sha256_checksum": "a1b2c3d4e5f6"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(GitHubRunnerDownloadDTO.self, from: json)
        #expect(dto.os == "osx")
        #expect(dto.architecture == "arm64")
        #expect(dto.filename == "actions-runner-osx-arm64-2.338.2.tar.gz")
        #expect(dto.sha256Checksum == "a1b2c3d4e5f6")
    }

    @Test("RunnerStatus, AppLanguage, and SidebarSection metadata mappings")
    func enumMetadataMappings() {
        #expect(RunnerStatus.idle.badgeTitle == "IDLE")
        #expect(RunnerStatus.busy.badgeTitle == "BUSY")
        #expect(RunnerStatus.faulted.badgeTitle == "FAULTED")
        #expect(AppLanguage.german.displayTitle.contains("Deutsch"))
        #expect(SidebarSection.allCases.count == 5)
    }

    @Test("HostTelemetryActor reads Apple Silicon CPU and memory metrics")
    func hostTelemetryMetrics() async {
        let actor = HostTelemetryActor()
        let snapshot = await actor.currentSnapshot()
        #expect(snapshot.totalCoreCount > 0)
        #expect(snapshot.physicalMemoryGB > 0)
        #expect(!snapshot.cpuSummary.isEmpty)
    }
}
