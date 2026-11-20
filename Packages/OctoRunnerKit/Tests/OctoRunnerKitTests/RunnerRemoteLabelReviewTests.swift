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
        let snapshot = try await fixture.snapshot()
        let review = try fixture.review(snapshot)
        #expect(fixture.runner.labels == ["local"])
        #expect(review.githubLabels == ["self-hosted", "xcode"])
        #expect(try review.apply(snapshot: snapshot, in: fixture.context))
        #expect(fixture.runner.labels == ["self-hosted", "xcode"])
        #expect(try fixture.context.fetch(FetchDescriptor<AuditLogEntity>()).contains { $0.targetRunnerName == "fixture" })
    }

    @Test("Changed account, identity or local labels invalidate a label review", arguments: ["account", "runner", "labels"])
    func rejectsStaleConfirmation(_ change: String) async throws {
        let fixture = try Fixture()
        let snapshot = try await fixture.snapshot()
        let review = try fixture.review(snapshot)
        switch change {
        case "account":
            try GitHubAccountStore.activate(accountID: fixture.account.id, in: fixture.context)
        case "runner":
            fixture.runner.githubRunnerId = 92
        default:
            fixture.runner.labels = ["new-local"]
        }
        #expect(try !review.apply(snapshot: snapshot, in: fixture.context))
        #expect(fixture.runner.labels != review.githubLabels)
    }

    @Test("A dismissed GitHub observation cannot be adopted from an old confirmation")
    func rejectsDiscardedObservation() async throws {
        let fixture = try Fixture()
        let snapshot = try await fixture.snapshot()
        let review = try fixture.review(snapshot)

        #expect(try !review.apply(snapshot: nil, in: fixture.context))
        #expect(fixture.runner.labels == ["local"])
    }

    @Test("Confirmed label updates preserve read-only labels and require the same selection and draft")
    func preparesVerifiedGitHubWrite() async throws {
        let fixture = try Fixture()
        let snapshot = try await fixture.snapshot()
        let update = try #require(RunnerRemoteLabelUpdate(snapshot: snapshot, runner: fixture.runner,
            account: fixture.account, draft: ["self-hosted", "xcode", "fastlane"]))
        #expect(update.customLabels == ["xcode", "fastlane"])
        #expect(try update.isCurrent(in: fixture.context))
        #expect(update.verifiesResult(["self-hosted", "xcode", "fastlane"]))
        #expect(!update.verifiesResult(["self-hosted", "xcode"]))
        try GitHubAccountStore.activate(accountID: fixture.account.id, in: fixture.context)
        #expect(try !update.isCurrent(in: fixture.context))
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

        func review(_ latest: RunnerSyncSnapshot) throws -> RunnerRemoteLabelReview {
            return try #require(RunnerRemoteLabelReview(snapshot: latest, runner: runner, account: account))
        }

        func snapshot() async throws -> RunnerSyncSnapshot {
            let data = Data(#"{"id":91,"name":"fixture","os":"macOS","status":"offline","busy":false,"labels":[{"name":"self-hosted","type":"read-only"},{"name":"xcode","type":"custom"}]}"#.utf8)
            let remote = try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: data)
            let monitor = RunnerRemoteSyncMonitor(scheduler: RunnerSyncScheduler { _, _, _, _ in
                .found(remote, eTag: nil)
            })
            await monitor.refresh(in: context)
            return try #require(monitor.snapshot)
        }
    }
}
