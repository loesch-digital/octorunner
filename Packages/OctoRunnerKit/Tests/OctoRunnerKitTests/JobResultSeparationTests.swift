import AppKit
@testable import AppShellFeature
import CoreModels
import SwiftData
import SwiftUI
import Testing

@MainActor
struct JobResultSeparationTests {
    private static var containers: [ModelContainer] = []

    @Test("An idle runner and a failed job remain visually distinct in the menu")
    func menuShowsSeparateFailure() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        let context = container.mainContext
        let account = GitHubAccountEntity(githubUserId: 7, login: "fixture", keychainAccountKey: "fixture")
        let runner = RunnerEntity(name: "local-mac", scopeUrl: URL(string: "https://github.com/example/repo")!, status: .idle, workDirectory: URL(fileURLWithPath: "/tmp/unused"))
        runner.githubRunnerId = 31
        context.insert(account)
        context.insert(runner)
        let job = JobRunEntity(githubRunId: 42, workflowName: "UI Tests", repositoryFullName: "example/repo", branchName: "main", commitSha: "abc")
        job.sourceRaw = "github"; job.recordKindRaw = "job"; job.githubJobId = 100
        job.accountGitHubUserID = 7; job.runAttempt = 1; job.conclusion = "failure"
        job.githubRunnerIDSnapshot = 31; job.completedAt = .now.addingTimeInterval(-5); job.observedAt = .now
        context.insert(job)
        try context.save()
        let suite = "job-separation-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let services = AppServices(preferences: AppPreferencesStore(defaults: defaults))
        for scheme in [ColorScheme.light, .dark] {
            let host = NSHostingView(rootView: MenuBarStatusView().modelContainer(container)
                .environment(services.preferences).environment(services.integration).environment(\.colorScheme, scheme))
            host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
            host.frame = NSRect(x: 0, y: 0, width: 350, height: 460)
            host.layoutSubtreeIfNeeded()
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let hasRed = (0..<bitmap.pixelsWide).contains { x in
                (0..<bitmap.pixelsHigh).contains { y in
                    guard let p = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return false }
                    return p.alphaComponent > 0.5 && p.redComponent > p.greenComponent + 0.3 && p.redComponent > p.blueComponent + 0.3
                }
            }
            #expect(hasRed, "Failed job must be visible separately while runner remains idle")
            #expect(runner.status == .idle)
            if let path = ProcessInfo.processInfo.environment["OCTORUNNER_JOB_RESULT_CAPTURE_DIR"] {
                try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                    URL(fileURLWithPath: path).appending(path: "job-result-menu-\(scheme == .dark ? "dark" : "light").png"))
                let row = NSHostingView(rootView: DashboardRunnerRow(runner: runner, lastJob: WorkflowHistoryEntry(job), openLog: {}, openSettings: {}, migrate: {}, remove: {})
                    .environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "de")))
                row.appearance = host.appearance
                row.frame = NSRect(x: 0, y: 0, width: 560, height: 250)
                row.layoutSubtreeIfNeeded()
                let rowBitmap = try #require(row.bitmapImageRepForCachingDisplay(in: row.bounds))
                row.cacheDisplay(in: row.bounds, to: rowBitmap)
                try #require(rowBitmap.representation(using: .png, properties: [:])).write(to:
                    URL(fileURLWithPath: path).appending(path: "job-result-row-\(scheme == .dark ? "dark" : "light").png"))
            }
        }
    }

    @Test("Only exact, unique local runner identities in the active account contribute",
          arguments: ["matching", "foreign-account", "wrong-repo", "name-only", "ambiguous", "foreign-host", "personal", "organization", "wrong-org", "org-query", "missing-time", "future-time", "missing-attempt"])
    func attribution(_ scenario: String) {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runner = fixtureRunner()
        let job = fixtureJob(now: now)
        var runners = [runner]
        switch scenario {
        case "foreign-account": job.accountGitHubUserID = 8
        case "wrong-repo": job.repositoryFullName = "example/other"
        case "name-only": job.githubRunnerIDSnapshot = nil; job.runnerNameSnapshot = runner.name
        case "ambiguous": runners.append(fixtureRunner())
        case "foreign-host": runner.scopeUrlString = "https://example.invalid/example/repo"
        case "personal": runner.scopeType = .personalMultiRepo
        case "organization": runner.scopeType = .organization; runner.scopeUrlString = "https://github.com/example"
        case "wrong-org": runner.scopeType = .organization; runner.scopeUrlString = "https://github.com/other"
        case "org-query": runner.scopeType = .organization; runner.scopeUrlString = "https://github.com/example?test=1"
        case "missing-time": job.completedAt = nil
        case "future-time": job.completedAt = now.addingTimeInterval(100)
        case "missing-attempt": job.runAttempt = nil
        default: break
        }
        let results = LocalJobResults(entries: [WorkflowHistoryEntry(job)], runners: runners, accountID: 7, reviewed: [], now: now)
        let expected = ["matching", "organization"].contains(scenario) ? 1 : 0
        #expect(results.latestByRunner.count == expected)
        #expect(results.unreviewedFailures.count == expected)
        #expect(runner.status == .idle)
        #expect(LocalJobResults(entries: [WorkflowHistoryEntry(job)], runners: runners, accountID: nil, reviewed: [], now: now).latestByRunner.isEmpty)
    }

    @Test("Acknowledgement persists across restarts without hiding the last failed result or a delayed failure")
    func reviewPersistence() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runner = fixtureRunner()
        let job = fixtureJob(now: now)
        let older = fixtureJob(now: now.addingTimeInterval(-100)); older.githubJobId = 101
        let suite = "job-result-review-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let first = LocalJobResults(entries: [WorkflowHistoryEntry(job)], runners: [runner], accountID: 7, reviewed: [], now: now)
        preferences.reviewedJobFailures.formUnion(first.unreviewedFailures.map(LocalJobResults.reviewKey))
        let restored = AppPreferencesStore(defaults: defaults)
        let second = LocalJobResults(entries: [WorkflowHistoryEntry(older), WorkflowHistoryEntry(job)], runners: [runner], accountID: 7, reviewed: restored.reviewedJobFailures, now: now)
        #expect(second.latestByRunner[runner.id]?.conclusion == "failure")
        #expect(second.unreviewedFailures.map(\.githubJobID) == [101])
        #expect(runner.status == .idle)
    }

    @Test("Newest attempts suppress prior failures; latest completed result is selected by completion time")
    func attemptsAndCompletion() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let runner = fixtureRunner()
        let old = fixtureJob(now: now.addingTimeInterval(-100))
        let retry = fixtureJob(now: now); retry.runAttempt = 2; retry.githubJobId = 101; retry.conclusion = "success"
        let other = fixtureJob(now: now.addingTimeInterval(-50)); other.githubRunId = 43; other.githubJobId = 102
        let results = LocalJobResults(entries: [other, old, retry].map(WorkflowHistoryEntry.init), runners: [runner], accountID: 7, reviewed: [], now: now)
        #expect(results.latestByRunner[runner.id]?.githubJobID == 101)
        #expect(results.unreviewedFailures.map(\.githubJobID) == [102])
        retry.statusRaw = "in_progress"; retry.completedAt = nil
        let pending = LocalJobResults(entries: [old, retry].map(WorkflowHistoryEntry.init), runners: [runner], accountID: 7, reviewed: [], now: now)
        #expect(pending.unreviewedFailures.isEmpty)
        #expect(pending.latestByRunner[runner.id]?.githubJobID == 100)
    }

    @Test("Failure hints are localized and distinguish one failure from several")
    func localizedFailureCount() {
        #expect(JobFailureNotice.title(1, locale: Locale(identifier: "en")) == "1 unreviewed failed job")
        #expect(JobFailureNotice.title(2, locale: Locale(identifier: "en")) == "2 unreviewed failed jobs")
        #expect(JobFailureNotice.title(1, locale: Locale(identifier: "de")) == "1 nicht quittierter Job-Fehler")
    }

    private func fixtureRunner() -> RunnerEntity {
        let runner = RunnerEntity(name: "local-mac", scopeUrl: URL(string: "https://github.com/example/repo")!, status: .idle, workDirectory: URL(fileURLWithPath: "/tmp/unused"))
        runner.githubRunnerId = 31
        return runner
    }

    private func fixtureJob(now: Date) -> JobRunEntity {
        let job = JobRunEntity(githubRunId: 42, workflowName: "UI Tests", repositoryFullName: "example/repo", branchName: "main", commitSha: "abc")
        job.sourceRaw = "github"; job.recordKindRaw = "job"; job.githubJobId = 100
        job.accountGitHubUserID = 7; job.runAttempt = 1; job.conclusion = "failure"
        job.githubRunnerIDSnapshot = 31; job.completedAt = now.addingTimeInterval(-5); job.observedAt = now
        return job
    }
}
