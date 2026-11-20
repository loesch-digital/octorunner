@testable import AppShellFeature
import CoreModels
import Foundation
import SwiftData
import SyncKit
import Testing

@MainActor
struct RunnerRemoteLabelReviewTests {
    @Test("Verified GitHub labels are adopted locally only after explicit confirmation")
    func acceptsVerifiedLabels() async throws {
        let fixture = try Fixture()
        let review = try await fixture.review()
        #expect(fixture.runner.labels == ["local"])
        #expect(review.githubLabels == ["self-hosted", "xcode"])
        #expect(try review.apply(in: fixture.context))
        #expect(fixture.runner.labels == ["self-hosted", "xcode"])
        #expect(try fixture.context.fetch(FetchDescriptor<AuditLogEntity>()).contains { $0.targetRunnerName == "fixture" })
    }

    @Test("Changed account, identity or local labels invalidate a label review", arguments: ["account", "runner", "labels"])
    func rejectsStaleConfirmation(_ change: String) async throws {
        let fixture = try Fixture()
        let review = try await fixture.review()
        switch change {
        case "account":
            try GitHubAccountStore.activate(accountID: fixture.account.id, in: fixture.context)
        case "runner":
            fixture.runner.githubRunnerId = 92
        default:
            fixture.runner.labels = ["new-local"]
        }
        #expect(try !review.apply(in: fixture.context))
        #expect(fixture.runner.labels != review.githubLabels)
    }

    @MainActor
    private struct Fixture {
        let container: ModelContainer
        let runner: RunnerEntity
        let account: GitHubAccountEntity
        var context: ModelContext { container.mainContext }

        init() throws {
            container = try OctoRunnerPersistence.makeInMemoryContainer()
            let scope = try #require(URL(string: "https://github.com/example/runner"))
            runner = RunnerEntity(name: "fixture", scopeUrl: scope, labels: ["local"],
                workDirectory: URL(filePath: "/tmp/label-review/_work"), isImportedLocal: true)
            account = GitHubAccountEntity(githubUserId: 1, login: "fixture-user", keychainAccountKey: "fixture")
            runner.githubRunnerId = 91
            context.insert(runner)
            context.insert(account)
            try context.save()
        }

        func review() async throws -> RunnerRemoteLabelReview {
            let data = Data(#"{"id":91,"name":"fixture","os":"macOS","status":"offline","busy":false,"labels":[{"name":"self-hosted"},{"name":"xcode"}]}"#.utf8)
            let remote = try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: data)
            let monitor = RunnerRemoteSyncMonitor(scheduler: RunnerSyncScheduler { _, _, _, _ in
                .found(remote, eTag: nil)
            })
            await monitor.refresh(in: context)
            let snapshot = try #require(monitor.snapshot)
            return try #require(RunnerRemoteLabelReview(snapshot: snapshot, runner: runner, account: account))
        }
    }
}
