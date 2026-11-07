import AppKit
import AppShellFeature
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

    @Test("GitHubDeviceCodeResponse and GitHubOAuthTokenResponse RFC 8628 JSON decoding")
    func oauthDeviceCodeAndTokenDecoding() throws {
        let deviceCodeJSON = """
        {
          "device_code": "3584d83530557fdd1f46af8289938c8ef79f9dc5",
          "user_code": "WDX8-8222",
          "verification_uri": "https://github.com/login/device",
          "expires_in": 900,
          "interval": 5
        }
        """.data(using: .utf8)!

        let decodedCode = try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: deviceCodeJSON)
        #expect(decodedCode.userCode == "WDX8-8222")
        #expect(decodedCode.expiresIn == 900)
        #expect(decodedCode.interval == 5)

        let pendingJSON = """
        {
          "error": "authorization_pending",
          "error_description": "The authorization request is still pending."
        }
        """.data(using: .utf8)!
        let decodedPending = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: pendingJSON)
        #expect(decodedPending.error == "authorization_pending")
        #expect(decodedPending.accessToken == nil)

        let tokenJSON = """
        {
          "access_token": "gho_16C7e42F292c6912E7710c838347Ae178B4a",
          "token_type": "bearer",
          "scope": "admin:org,repo,workflow"
        }
        """.data(using: .utf8)!
        let decodedToken = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: tokenJSON)
        #expect(decodedToken.accessToken == "gho_16C7e42F292c6912E7710c838347Ae178B4a")
        #expect(decodedToken.error == nil)
    }

    @Test("GitHubOAuthActor X-OAuth-Scopes header parsing and default Client ID")
    func oauthScopesParsingAndConfig() {
        #expect(GitHubOAuthConfig.defaultClientID == "Ov23liD1qcIUTp8adWQd")
        let scopes = GitHubOAuthActor.parseScopes(from: "repo, workflow, admin:org")
        #expect(scopes == ["repo", "workflow", "admin:org"])
        #expect(GitHubOAuthActor.parseScopes(from: "").isEmpty)
    }

    @Test("In-memory SwiftData GitHubAccountEntity persistence without storing raw secret")
    @MainActor
    func githubAccountEntityPersistence() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: GitHubAccountEntity.self, configurations: config)
        let context = container.mainContext

        let account = GitHubAccountEntity(
            githubUserId: 123456,
            login: "loesch-digital",
            displayName: "Frank",
            scopes: ["repo", "workflow", "admin:org"],
            authMethodRaw: "oauth_device",
            keychainAccountKey: "loesch-digital"
        )
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GitHubAccountEntity>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.login == "loesch-digital")
        #expect(fetched.first?.scopes.contains("workflow") == true)
    }

    @Test("OAuthDeviceFlowViewModel copies userCode to NSPasteboard and resets cleanly on cancel")
    @MainActor
    func oauthDeviceFlowClipboardCopyAndCancelState() {
        let viewModel = OAuthDeviceFlowViewModel()
        viewModel.copyUserCode("ABCD-9876")
        #expect(viewModel.copiedToClipboard == true)
        #expect(NSPasteboard.general.string(forType: .string) == "ABCD-9876")

        viewModel.cancelFlow()
        #expect(viewModel.state == .initial)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("AppUpdaterActor semantic version comparison and GitHubReleaseDTO decoding")
    func appUpdaterVersionComparisonAndDecoding() throws {
        #expect(AppUpdaterActor.isVersion("v0.2.2", newerThan: "0.2.1") == true)
        #expect(AppUpdaterActor.isVersion("0.3.0", newerThan: "0.2.9") == true)
        #expect(AppUpdaterActor.isVersion("0.2.1", newerThan: "0.2.1") == false)
        #expect(AppUpdaterActor.isVersion("0.1.9", newerThan: "0.2.0") == false)

        let releaseJSON = """
        {
          "tag_name": "v0.2.2",
          "name": "OctoRunner v0.2.2",
          "body": "Auto-updater and account profile menu.",
          "html_url": "https://github.com/loesch-digital/octorunner/releases/tag/v0.2.2",
          "published_at": "2026-11-07T16:00:00Z",
          "assets": [
            {
              "name": "OctoRunner-0.2.2-arm64.zip",
              "browser_download_url": "https://github.com/loesch-digital/octorunner/releases/download/v0.2.2/OctoRunner-0.2.2-arm64.zip",
              "size": 1245184
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GitHubReleaseDTO.self, from: releaseJSON)
        #expect(decoded.tagName == "v0.2.2")
        #expect(decoded.assets.first?.name == "OctoRunner-0.2.2-arm64.zip")
    }
}
