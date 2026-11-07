import CoreModels
import Foundation
import SwiftData
import Testing

@Suite("CoreModels & SwiftData Persistence Tests")
struct CoreModelsTests {
    @Test("RunnerEntity and JobRunEntity creation, computed properties, and cascade delete")
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
        #expect(fetchedRunners.first?.scopeType == .repository)
        #expect(fetchedRunners.first?.jobRuns.count == 1)
        #expect(fetchedRunners.first?.serviceLabel == "io.octorunner.agent.mac-runner-test")

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
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: GitHubAccountEntity.self, configurations: config)
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
        #expect(RunnerStatus.busy.badgeTitle == "BUSY")
        #expect(RunnerStatus.offline.badgeTitle == "OFFLINE")
        #expect(RunnerStatus.faulted.badgeTitle == "FAULTED")

        #expect(RunnerScopeType.repository.displayTitle == "Repository")
        #expect(RunnerScopeType.organization.displayTitle == "Organization")
        #expect(RunnerScopeType.personalMultiRepo.displayTitle.contains("Personal"))

        #expect(AppLanguage.english.displayTitle.contains("English"))
        #expect(AppLanguage.german.displayTitle.contains("Deutsch"))

        #expect(SidebarSection.allCases.count == 5)
        for section in SidebarSection.allCases {
            #expect(!section.title.isEmpty)
            #expect(!section.systemImage.isEmpty)
        }
    }
}
