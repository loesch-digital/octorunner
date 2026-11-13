import AppShellFeature
import CoreModels
import Foundation
import GitHubAPI
import SwiftData
import Testing

@MainActor
struct LocalJobFailureMonitorTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Job monitoring performs no requests or permission prompts without both opt-ins")
    func optIn() async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        await env.monitor.refresh(in: env.context, now: start)
        env.preferences.notificationPolicy.enabled = true
        env.preferences.notificationPolicy.jobFailure = false
        await env.monitor.refresh(in: env.context, now: start)
        #expect(await env.loader.requests.isEmpty)
        #expect(await env.client.permissionRequests == 0)
        #expect(try env.context.fetchCount(FetchDescriptor<JobRunEntity>()) == 0)
    }

    @Test("Only newly completed local job failures alert once; startup history is silent")
    func newFailure() async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        await env.loader.set(page: try page(completed: start.addingTimeInterval(-10), observed: start))
        await env.monitor.refresh(in: env.context, now: start)
        #expect(await env.client.events.isEmpty)
        await env.loader.set(page: try page(completed: start.addingTimeInterval(5), observed: start.addingTimeInterval(10)))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(10))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(20))
        let event = try #require(await env.client.events.first)
        #expect(await env.client.events.count == 1)
        #expect(event.kind == .jobFailure)
        #expect(event.message.contains("example/repo") && event.message.contains("local-mac"))
        #expect(!event.message.contains("REMOTE-JOB-TEXT"))
        #expect(try env.context.fetchCount(FetchDescriptor<JobRunEntity>()) == 2)
        #expect(await env.client.permissionRequests == 0)
    }

    @Test("Runner ID and exact GitHub scope must agree; a matching name alone is insufficient",
          arguments: ["wrong-id", "wrong-repository", "foreign-host", "scope-query", "unknown-id", "ambiguous", "personal", "organization", "wrong-organization", "organization-double-slash"])
    func runnerAttribution(_ scenario: String) async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        let runner = env.runner
        switch scenario {
        case "wrong-id": runner.githubRunnerId = 99
        case "wrong-repository": runner.scopeUrlString = "https://github.com/example/other"
        case "foreign-host": runner.scopeUrlString = "https://example.invalid/example/repo"
        case "scope-query": runner.scopeUrlString += "?token=synthetic"
        case "unknown-id": runner.githubRunnerId = nil
        case "ambiguous":
            let duplicate = RunnerEntity(name: "another", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: URL(fileURLWithPath: "/tmp/unused"))
            duplicate.githubRunnerId = 31
            env.context.insert(duplicate)
        case "personal": runner.scopeType = .personalMultiRepo
        case "organization": runner.scopeType = .organization; runner.scopeUrlString = "https://github.com/example/"
        case "organization-double-slash": runner.scopeType = .organization; runner.scopeUrlString = "https://github.com//example//"
        default: runner.scopeType = .organization; runner.scopeUrlString = "https://github.com/other"
        }
        env.preferences.historyPreferences.additionalRepositoriesByAccount["7"] = ["example/repo"]
        await env.monitor.refresh(in: env.context, now: start)
        await env.loader.set(page: try page(completed: start.addingTimeInterval(5), observed: start.addingTimeInterval(10)))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(10))
        #expect(await env.client.events.count == (scenario == "organization" ? 1 : 0))
    }

    @Test("Success, cancellation, missing completion and invalid future timestamps never alert",
          arguments: ["success", "cancelled", "skipped", "in_progress", "missing-time", "future-time"])
    func nonFailures(_ scenario: String) async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        await env.monitor.refresh(in: env.context, now: start)
        let completion: Date? = scenario == "missing-time" ? nil : start.addingTimeInterval(scenario == "future-time" ? 100 : 5)
        await env.loader.set(page: try page(completed: completion, observed: start.addingTimeInterval(10), conclusion: ["missing-time", "future-time"].contains(scenario) ? "failure" : scenario))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(10))
        #expect(await env.client.events.isEmpty)
    }

    @Test("A newer run attempt suppresses an older failure")
    func retryAttempt() async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        await env.monitor.refresh(in: env.context, now: start)
        let failed = try page(completed: start.addingTimeInterval(5), observed: start.addingTimeInterval(10))
        let successful = try page(completed: start.addingTimeInterval(8), observed: start.addingTimeInterval(10), conclusion: "success", attempt: 2)
        await env.loader.set(page: WorkflowHistoryPage(runs: failed.runs + successful.runs, nextPage: nil, rateLimit: nil, observedAt: start.addingTimeInterval(10)))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(10))
        #expect(await env.client.events.isEmpty)
    }

    @Test("A delivery failure is retried without losing jobs completed at the same instant")
    func failedDelivery() async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        await env.monitor.refresh(in: env.context, now: start)
        let first = try page(completed: start.addingTimeInterval(5), observed: start.addingTimeInterval(10))
        let second = try page(completed: start.addingTimeInterval(5), observed: start.addingTimeInterval(10), jobID: 101)
        let details = WorkflowRunDetails(run: first.runs[0].run, jobs: first.runs[0].jobs! + second.runs[0].jobs!)
        await env.loader.set(page: WorkflowHistoryPage(runs: [details], nextPage: nil, rateLimit: nil, observedAt: start.addingTimeInterval(10)))
        await env.client.setFailure(true)
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(10))
        #expect(await env.client.events.isEmpty)
        await env.client.setFailure(false)
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(20))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(30))
        #expect(await env.client.events.count == 2)
        #expect(Set(await env.client.events.map(\.id)).count == 2)
    }

    @Test("Late network responses after account changes, consent changes or stop cannot write history",
          arguments: ["account", "key", "disabled", "consent-cycle", "stop", "cancel", "source"])
    func lateResponse(_ change: String) async throws {
        let gate = GatedJobHistoryLoader(page: try page(completed: start.addingTimeInterval(1), observed: start.addingTimeInterval(2)))
        let env = try JobMonitorEnvironment(loader: gate)
        defer { env.cleanDefaults() }
        env.enable()
        let task = Task { await env.monitor.refresh(in: env.context, now: start) }
        await gate.waitForStart()
        switch change {
        case "account": env.account.isActive = false
        case "key": env.account.keychainAccountKey = "rotated-key"
        case "disabled": env.preferences.notificationPolicy.jobFailure = false
        case "consent-cycle":
            env.preferences.notificationPolicy.jobFailure = false
            env.preferences.notificationPolicy.jobFailure = true
        case "stop": env.monitor.stop()
        case "source": env.runner.scopeUrlString = "https://github.com/example/other"
        default: task.cancel()
        }
        await gate.release()
        await task.value
        #expect(await env.client.events.isEmpty)
        #expect(try env.context.fetchCount(FetchDescriptor<JobRunEntity>()) == 0)
    }

    @Test("Job polling shares the account rate budget with the visible history")
    func sharedBudget() async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        await env.loader.set(error: .rateLimited(until: .now.addingTimeInterval(3600)))
        await env.monitor.refresh(in: env.context)
        await env.monitor.refresh(in: env.context)
        let model = WorkflowHistoryViewModel(loader: env.loader, rateBudget: env.budget)
        try model.select(WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture-key", repository: "example/repo"), in: env.context)
        await model.load(in: env.context)
        #expect(await env.loader.requests.count == 1)
        #expect(model.retryNotBefore != nil)
    }

    @Test("Explicitly re-enabling alerts establishes a new baseline and uses German messages")
    func reenable() async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        env.preferences.language = .german
        await env.monitor.refresh(in: env.context, now: start)
        env.preferences.notificationPolicy.enabled = false
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(10))
        env.enable()
        await env.loader.set(page: try page(completed: start.addingTimeInterval(5), observed: start.addingTimeInterval(20)))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(20))
        #expect(await env.client.events.isEmpty)
        await env.loader.set(page: try page(completed: start.addingTimeInterval(25), observed: start.addingTimeInterval(30), conclusion: "timed_out"))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(30))
        #expect(await env.client.events.first?.title == "Lokaler Workflow-Job fehlgeschlagen")
    }

    @Test("Switching notifications off and on between polls still resets the failure baseline")
    func consentBetweenPolls() async throws {
        let env = try JobMonitorEnvironment()
        defer { env.cleanDefaults() }
        env.enable()
        await env.monitor.refresh(in: env.context, now: start)
        env.preferences.notificationPolicy.enabled = false
        env.preferences.notificationPolicy.enabled = true
        await env.loader.set(page: try page(completed: start.addingTimeInterval(5), observed: start.addingTimeInterval(10)))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(10))
        #expect(await env.client.events.isEmpty)
        await env.loader.set(page: try page(completed: start.addingTimeInterval(15), observed: start.addingTimeInterval(20)))
        await env.monitor.refresh(in: env.context, now: start.addingTimeInterval(20))
        #expect(await env.client.events.count == 1)
    }

    private func page(completed: Date?, observed: Date, conclusion: String = "failure", attempt: Int = 1, jobID: Int = 100) throws -> WorkflowHistoryPage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let completion = completed.map { "\"\(ISO8601DateFormatter().string(from: $0))\"" } ?? "null"
        let run = try decoder.decode(GitHubWorkflowRunDTO.self, from: Data("{\"id\":42,\"status\":\"completed\",\"conclusion\":\"\(conclusion)\",\"run_attempt\":\(attempt)}".utf8))
        let job = try decoder.decode(GitHubWorkflowJobDTO.self, from: Data("{\"id\":\(jobID),\"run_id\":42,\"name\":\"REMOTE-JOB-TEXT\",\"status\":\"\(conclusion == "in_progress" ? "in_progress" : "completed")\",\"conclusion\":\"\(conclusion)\",\"completed_at\":\(completion),\"runner_id\":31,\"runner_name\":\"local-mac\"}".utf8))
        return WorkflowHistoryPage(runs: [WorkflowRunDetails(run: run, jobs: [job])], nextPage: nil, rateLimit: nil, observedAt: observed)
    }
}

@MainActor
private struct JobMonitorEnvironment {
    private let container: ModelContainer
    let context: ModelContext
    let account: GitHubAccountEntity
    let runner: RunnerEntity
    let preferences: AppPreferencesStore
    let client = JobMonitorNotificationClient()
    let loader = FixtureJobHistoryLoader()
    let budget = WorkflowHistoryRateBudget()
    let monitor: LocalJobFailureMonitor
    private let suite = "job-monitor-\(UUID())"
    private let defaults: UserDefaults

    init(loader injected: (any WorkflowHistoryLoading)? = nil) throws {
        container = try OctoRunnerPersistence.makeInMemoryContainer()
        context = container.mainContext
        defaults = try #require(UserDefaults(suiteName: suite))
        preferences = AppPreferencesStore(defaults: defaults)
        account = GitHubAccountEntity(githubUserId: 7, login: "fixture", keychainAccountKey: "fixture-key")
        runner = RunnerEntity(name: "local-mac", scopeUrl: URL(string: "https://github.com/example/repo")!, workDirectory: URL(fileURLWithPath: "/tmp/unused-work"))
        runner.githubRunnerId = 31
        context.insert(account)
        context.insert(runner)
        try context.save()
        monitor = LocalJobFailureMonitor(preferences: preferences,
            notifications: AppNotificationsController(preferences: preferences, client: client),
            rateBudget: budget, loader: injected ?? loader)
    }

    func enable() { preferences.notificationPolicy.enabled = true; preferences.notificationPolicy.jobFailure = true }
    func cleanDefaults() { defaults.removePersistentDomain(forName: suite) }
}

private actor FixtureJobHistoryLoader: WorkflowHistoryLoading {
    private(set) var requests: [WorkflowHistorySelection] = []
    private var value = WorkflowHistoryPage(runs: [], nextPage: nil, rateLimit: nil, observedAt: .now)
    private var error: WorkflowHistoryLoadError?
    func set(page: WorkflowHistoryPage) { value = page; error = nil }
    func set(error: WorkflowHistoryLoadError) { self.error = error }
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) throws -> WorkflowHistoryPage {
        requests.append(selection)
        if let error { throw error }
        guard selection.repository == "example/repo" else {
            return WorkflowHistoryPage(runs: [], nextPage: nil, rateLimit: nil, observedAt: value.observedAt)
        }
        return value
    }
}

private actor GatedJobHistoryLoader: WorkflowHistoryLoading {
    private let value: WorkflowHistoryPage
    private let started = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()
    init(page: WorkflowHistoryPage) { value = page }
    func waitForStart() async { for await _ in started.stream { break } }
    func release() { gate.continuation.finish() }
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async -> WorkflowHistoryPage {
        started.continuation.yield(())
        for await _ in gate.stream { }
        return value
    }
}

private actor JobMonitorNotificationClient: AppNotificationClient {
    private(set) var events: [AppNotificationEvent] = []
    private(set) var permissionRequests = 0
    private var failure = false
    func setFailure(_ value: Bool) { failure = value }
    func authorizationStatus() -> NotificationAuthorizationState { .allowed }
    func requestAuthorization() -> Bool { permissionRequests += 1; return true }
    func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) throws {
        if failure { throw CocoaError(.fileWriteUnknown) }
        events.append(event)
    }
}
