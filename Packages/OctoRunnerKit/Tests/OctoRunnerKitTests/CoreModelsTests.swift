import CoreModels
import Foundation
import SwiftData
import Testing

@Suite("CoreModels & SwiftData Persistence Tests", .serialized)
struct CoreModelsTests {
    @Test("RunnerEntity and JobRunEntity creation, computed properties, and cascade delete")
    @MainActor
    func runnerEntityPersistenceAndCascadeDelete() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext

        let runner = RunnerEntity(
            name: "mac-runner-test",
            scopeType: .repository,
            scopeUrl: URL(string: "https://github.com/loesch-digital/octorunner")!,
            status: .idle,
            labels: ["self-hosted", "macos", "arm64"],
            workDirectory: URL(fileURLWithPath: "/tmp/octorunner-test"),
            rootDirectoryPath: "/tmp/octorunner-root",
            runnerVersion: "2.338.2",
            isImportedLocal: true
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
        #expect(fetchedRunners.first?.scopeType == .repository)
        #expect(fetchedRunners.first?.jobRuns.count == 1)
        #expect(fetchedRunners.first?.serviceLabel == "io.octorunner.agent.mac-runner-test")
        #expect(fetchedRunners.first?.rootDirectoryPath == "/tmp/octorunner-root")
        #expect(fetchedRunners.first?.runnerVersion == "2.338.2")
        #expect(fetchedRunners.first?.isImportedLocal == true)

        // Verify status setter and scopeType setter
        runner.status = .busy
        runner.scopeType = .organization
        try context.save()
        #expect(runner.statusRaw == "busy")
        #expect(runner.scopeTypeRaw == "organization")

        // Verify cascade delete removes associated JobRunEntity
        context.delete(runner)
        try context.save()
        let remainingJobs = try context.fetch(FetchDescriptor<JobRunEntity>())
        #expect(remainingJobs.isEmpty)
    }

    @Test("GitHubAccountEntity persistence without storing raw secret")
    @MainActor
    func githubAccountEntityPersistence() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext

        let account = GitHubAccountEntity(
            githubUserId: 123456,
            login: "loesch-digital",
            displayName: "Frank",
            avatarUrlString: "https://avatars.githubusercontent.com/u/123456",
            scopes: ["repo", "workflow", "admin:org"],
            authMethodRaw: "oauth_device",
            keychainAccountKey: "loesch-digital"
        )
        context.insert(account)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<GitHubAccountEntity>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.login == "loesch-digital")
        #expect(fetched.first?.displayName == "Frank")
        #expect(fetched.first?.scopes.contains("workflow") == true)
        #expect(fetched.first?.isActive == true)
    }

    @Test("RunnerStatus, RunnerScopeType, AppLanguage, and SidebarSection metadata mappings")
    func enumMetadataMappings() {
        #expect(RunnerStatus.idle.badgeTitle == "IDLE")
        #expect(RunnerStatus.busy.badgeTitle == "RUNNING")
        #expect(RunnerStatus.busy.rawValue == "busy")
        #expect(RunnerStatus.offline.badgeTitle == "OFFLINE")
        #expect(RunnerStatus.faulted.badgeTitle == "FAULTED")

        #expect(RunnerScopeType.repository.displayTitle == "Repository")
        #expect(RunnerScopeType.organization.displayTitle == "Organization")
        #expect(RunnerScopeType.personalMultiRepo.displayTitle.contains("Personal"))

        #expect(AppLanguage.english.displayTitle.contains("English"))
        #expect(AppLanguage.german.displayTitle.contains("Deutsch"))

        #expect(SidebarSection.allCases.count == 5)
        #expect(SidebarSection.launchdSettings.title == "Settings")
        for section in SidebarSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.systemImage.isEmpty)
        }

        let parsedLog = RunnerLogLine.parse("[2026-11-07 18:10:00Z INFO Runner] Listening for Jobs", index: 1)
        #expect(parsedLog.level == .info)
        #expect(parsedLog.message.contains("Listening for Jobs"))
    }

    @Test("OctoRunnerPersistence recreates a store with an invalid SQLite header without fatalError")
    @MainActor
    func persistenceCorruptHeaderRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "octorunner-migration-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // 1. Test self-healing when store file contains corrupted/unreadable bytes
        let corruptedStoreURL = tempDir.appending(path: "corrupted.store")
        try Data("not-a-valid-sqlite-database".utf8).write(to: corruptedStoreURL)

        let healedContainer = OctoRunnerPersistence.makeSharedContainer(storeURL: corruptedStoreURL)
        let context = healedContainer.mainContext
        let runner = RunnerEntity(
            name: "healed-runner",
            scopeType: .repository,
            scopeUrl: URL(string: "https://github.com/loesch-digital/octorunner")!,
            workDirectory: tempDir
        )
        context.insert(runner)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "healed-runner")
        #expect(fetched.first?.isImportedLocal == false)
    }

    @Test("AuditLogEntity and AuditLogRecorder persist configuration changes and system events")
    @MainActor
    func auditLogPersistenceAndRecorder() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext

        AuditLogRecorder.record(
            in: context,
            category: .configuration,
            severity: .info,
            title: "Runner Labels Updated",
            summary: "Added 'fastlane' label to macbook-pro-frank",
            actorAccountLogin: "loesch-digital",
            targetRunnerName: "macbook-pro-frank",
            previousValue: "self-hosted,macOS,ARM64",
            newValue: "self-hosted,macOS,ARM64,fastlane"
        )

        AuditLogRecorder.record(
            in: context,
            category: .runnerLifecycle,
            severity: .warning,
            title: "Local Runner Imported",
            summary: "Auto-imported macbook-pro-frank (agentId 21, v2.338.2)",
            actorAccountLogin: "loesch-digital",
            targetRunnerName: "macbook-pro-frank"
        )

        let descriptor = FetchDescriptor<AuditLogEntity>(
            sortBy: [SortDescriptor(\AuditLogEntity.timestamp, order: .reverse)]
        )
        let logs = try context.fetch(descriptor)
        #expect(logs.count == 2)

        let configEntry = logs.first { $0.category == .configuration }
        #expect(configEntry != nil)
        #expect(configEntry?.severity == .info)
        #expect(configEntry?.title == "Runner Labels Updated")
        #expect(configEntry?.previousValue == "self-hosted,macOS,ARM64")
        #expect(configEntry?.newValue == "self-hosted,macOS,ARM64,fastlane")

        let lifecycleEntry = logs.first { $0.category == .runnerLifecycle }
        #expect(lifecycleEntry != nil)
        #expect(lifecycleEntry?.severity == .warning)
        #expect(lifecycleEntry?.targetRunnerName == "macbook-pro-frank")
    }
}
