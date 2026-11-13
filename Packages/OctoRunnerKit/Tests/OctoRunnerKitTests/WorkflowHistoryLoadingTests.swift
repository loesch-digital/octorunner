import CoreModels
import Foundation
@testable import GitHubAPI
import SecurityKit
import SwiftData
@testable import AppShellFeature
import Testing

@MainActor
struct WorkflowHistoryLoadingTests {
    private static var containers: [ModelContainer] = []
    private let selection = WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture-account", repository: "example/repo")

    @Test("A page loads attempt-specific jobs and keeps missing attempts unknown")
    func realLoader() async throws {
        let transport = HistoryHTTPFixture([
            #"{"total_count":2,"workflow_runs":[{"id":42,"run_attempt":2,"status":"completed","conclusion":"success"},{"id":43,"status":"queued"}]}"#,
            #"{"total_count":1,"jobs":[{"id":100,"run_id":42,"name":"Build","status":"completed","conclusion":"success"}]}"#
        ])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: HistorySecrets())
        let result = try await loader.page(selection: selection, nextPage: nil, completedAttempts: [])
        #expect(result.runs.count == 2)
        #expect(result.runs[0].jobs?.first?.id == 100)
        #expect(result.runs[1].jobs == nil)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests[0].url?.query?.contains("per_page=10") == true)
        #expect(requests[1].url?.path.contains("/attempts/2/jobs") == true)
    }

    @Test("Completed job details are cached while workflow status is refreshed")
    func cachedDetails() async throws {
        let transport = HistoryHTTPFixture([#"{"total_count":1,"workflow_runs":[{"id":42,"run_attempt":2,"status":"completed","conclusion":"success"}]}"#])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: HistorySecrets())
        let result = try await loader.page(selection: selection, nextPage: nil, completedAttempts: ["42/2"])
        #expect(result.runs.first?.jobs == nil)
        #expect(await transport.requests.count == 1)
    }

    @Test("A signed-out account never sends an API request")
    func missingSecret() async {
        let transport = HistoryHTTPFixture([])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: HistorySecrets(value: nil))
        await #expect(throws: WorkflowHistoryLoadError.authenticationRequired) {
            try await loader.page(selection: selection, nextPage: nil, completedAttempts: [])
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Permission errors and exhausted rate budgets remain distinct without exposing response bodies")
    func permissionAndRateLimit() async throws {
        let denied = HistoryHTTPFixture(responses: [GitHubActionsHTTPResponse(statusCode: 403, headers: [:], data: Data("untrusted body".utf8))])
        let deniedLoader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: denied), secrets: HistorySecrets())
        await #expect(throws: WorkflowHistoryLoadError.permissionDenied) {
            try await deniedLoader.page(selection: selection, nextPage: nil, completedAttempts: [])
        }
        let limited = HistoryHTTPFixture(responses: [GitHubActionsHTTPResponse(statusCode: 429, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"], data: Data())])
        let limitedLoader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: limited), secrets: HistorySecrets())
        await #expect(throws: WorkflowHistoryLoadError.rateLimited(until: Date(timeIntervalSince1970: 1_800_000_000))) {
            try await limitedLoader.page(selection: selection, nextPage: nil, completedAttempts: [])
        }
        #expect(await limited.requests.count == 1)
    }

    @Test("An earlier rate limit cannot turn a later headerless permission denial into a rate error")
    func requestScopedRateMetadata() async {
        let transport = HistoryHTTPFixture(responses: [
            GitHubActionsHTTPResponse(statusCode: 429, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"], data: Data()),
            GitHubActionsHTTPResponse(statusCode: 403, headers: [:], data: Data())
        ])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: HistorySecrets())
        await #expect(throws: WorkflowHistoryLoadError.rateLimited(until: Date(timeIntervalSince1970: 1_800_000_000))) {
            try await loader.page(selection: selection, nextPage: nil, completedAttempts: [])
        }
        await #expect(throws: WorkflowHistoryLoadError.permissionDenied) {
            try await loader.page(selection: selection, nextPage: nil, completedAttempts: [])
        }
    }

    @Test("An exhausted workflow response never triggers further job requests")
    func exhaustedBudget() async throws {
        let payload = #"{"total_count":1,"workflow_runs":[{"id":42,"run_attempt":1,"status":"queued"}]}"#
        let transport = HistoryHTTPFixture(responses: [GitHubActionsHTTPResponse(statusCode: 200, headers: ["X-RateLimit-Remaining": "0", "X-RateLimit-Reset": "1800000000"], data: Data(payload.utf8))])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: HistorySecrets())
        let result = try await loader.page(selection: selection, nextPage: nil, completedAttempts: [])
        #expect(result.runs.first?.jobs == nil)
        #expect(result.rateLimit?.remaining == 0)
        #expect(await transport.requests.count == 1)
    }

    @Test("Both Retry-After and an exhausted primary budget must be respected")
    func combinedRateDeadlines() async {
        let epoch = Int(Date.now.timeIntervalSince1970) + 3_600
        let deadline = Date(timeIntervalSince1970: Double(epoch))
        let transport = HistoryHTTPFixture(responses: [GitHubActionsHTTPResponse(statusCode: 429,
            headers: ["Retry-After": "60", "X-RateLimit-Remaining": "0", "X-RateLimit-Reset": String(epoch)], data: Data())])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: HistorySecrets())
        await #expect(throws: WorkflowHistoryLoadError.rateLimited(until: deadline)) {
            try await loader.page(selection: selection, nextPage: nil, completedAttempts: [])
        }
    }

    @Test("Rate backoff survives repository and account switching without blocking another account")
    func backoff() async throws {
        let context = try makeContext()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let deadline = now.addingTimeInterval(120)
        let loader = RateLimitedHistoryLoader(deadline: deadline, result: try page())
        let model = WorkflowHistoryViewModel(loader: loader)
        try model.select(selection, in: context)
        await model.load(in: context, refresh: true, now: now)
        #expect(model.retryNotBefore == deadline)
        await model.load(in: context, refresh: true, now: now.addingTimeInterval(10))
        try model.select(WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture-account", repository: "example/other"), in: context)
        await model.load(in: context, refresh: true, now: now.addingTimeInterval(10))
        #expect(await loader.calls == 1)
        try model.select(WorkflowHistorySelection(accountID: 8, keychainAccountKey: "other", repository: "example/other"), in: context)
        await model.load(in: context, refresh: true, now: now.addingTimeInterval(10))
        #expect(await loader.calls == 2)
        try model.select(selection, in: context)
        await model.load(in: context, refresh: true, now: now.addingTimeInterval(10))
        #expect(await loader.calls == 2)
        await model.load(in: context, refresh: true, now: deadline.addingTimeInterval(1))
        #expect(await loader.calls == 3 && model.retryNotBefore == nil)
    }

    @Test("Late rate metadata still protects its account after the selection changes", arguments: [true, false])
    func lateRateMetadata(successfulResponse: Bool) async throws {
        let context = try makeContext()
        let loader = GatedHistoryLoader()
        let model = WorkflowHistoryViewModel(loader: loader)
        let deadline = Date.now.addingTimeInterval(300)
        try model.select(selection, in: context)
        let task = Task { await model.load(in: context, refresh: true) }
        await loader.waitForRequest()
        try model.select(WorkflowHistorySelection(accountID: 8, keychainAccountKey: "other", repository: "example/other"), in: context)
        if successfulResponse {
            await loader.release(WorkflowHistoryPage(runs: [], nextPage: nil,
                rateLimit: GitHubRateLimitSnapshot(headers: ["x-ratelimit-remaining": "0", "x-ratelimit-reset": String(Int(deadline.timeIntervalSince1970))]), observedAt: .now))
        } else { await loader.fail(.rateLimited(until: deadline)) }
        await task.value
        try model.select(selection, in: context)
        let blockedUntil = try #require(model.retryNotBefore)
        #expect(blockedUntil.timeIntervalSince(deadline) > -1)
        await model.load(in: context, refresh: true)
        #expect(await loader.calls == 1)
        #expect(model.entries.isEmpty)
    }

    @Test("A late rate result cannot shorten a newer account deadline")
    func monotonicBackoff() async throws {
        let context = try makeContext()
        let longer = Date.now.addingTimeInterval(600)
        let loader = GatedHistoryLoader(subsequentError: .rateLimited(until: longer))
        let model = WorkflowHistoryViewModel(loader: loader)
        try model.select(selection, in: context)
        let old = Task { await model.load(in: context, refresh: true) }
        await loader.waitForRequest()
        try model.select(selection, in: context)
        await model.load(in: context, refresh: true)
        await loader.fail(.rateLimited(until: Date.now.addingTimeInterval(120)))
        await old.value
        #expect(model.retryNotBefore == longer)
    }

    @Test("Cyclic job pagination stops instead of looping or presenting partial details as complete")
    func cyclicJobs() async {
        let run = #"{"total_count":1,"workflow_runs":[{"id":42,"run_attempt":1,"status":"queued"}]}"#
        let jobs = #"{"total_count":2,"jobs":[]}"#
        let next = "https://api.github.com/repos/example/repo/actions/runs/42/attempts/1/jobs?per_page=100&page=2"
        let repeated = GitHubActionsHTTPResponse(statusCode: 200, headers: ["Link": "<\(next)>; rel=\"next\""], data: Data(jobs.utf8))
        let transport = HistoryHTTPFixture(responses: [GitHubActionsHTTPResponse(statusCode: 200, headers: [:], data: Data(run.utf8)), repeated, repeated])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: HistorySecrets())
        await #expect(throws: WorkflowHistoryLoadError.tooManyPages) {
            try await loader.page(selection: selection, nextPage: nil, completedAttempts: [])
        }
        #expect(await transport.requests.count == 3)
    }

    @Test("A pre-cancelled view task never invokes its loader")
    func cancelledBeforeLoad() async throws {
        let context = try makeContext()
        let loader = HistoryPageQueue([try page()])
        let model = WorkflowHistoryViewModel(loader: loader)
        try model.select(selection, in: context)
        await Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            await model.load(in: context, refresh: true)
        }.value
        #expect(await loader.requests.isEmpty)
        #expect(!model.isLoading && model.error == nil)
    }

    @Test("The view model saves pages, stops at the end and reuses completed attempt details on refresh")
    func pagePersistence() async throws {
        let context = try makeContext()
        let firstRun = try JSONDecoder().decode(GitHubWorkflowRunDTO.self, from: Data(#"{"id":42,"status":"completed","conclusion":"success","run_attempt":1}"#.utf8))
        let next = try #require(URL(string: "https://api.github.com/repos/example/repo/actions/runs?per_page=10&page=2"))
        let first = WorkflowHistoryPage(runs: [WorkflowRunDetails(run: firstRun, jobs: [])], nextPage: next, rateLimit: nil, observedAt: .now)
        let refresh = WorkflowHistoryPage(runs: [WorkflowRunDetails(run: firstRun, jobs: nil)], nextPage: next, rateLimit: nil, observedAt: .now)
        let loader = HistoryPageQueue([first, WorkflowHistoryPage(runs: [], nextPage: nil, rateLimit: nil, observedAt: .now), refresh])
        let model = WorkflowHistoryViewModel(loader: loader)
        try model.select(selection, in: context)
        await model.load(in: context, refresh: true)
        #expect(model.entries.count == 1 && model.nextPage == next && model.lastRefresh != nil)
        await model.load(in: context)
        await model.load(in: context)
        #expect(await loader.requests.count == 2)
        await model.load(in: context, refresh: true)
        #expect(model.entries.count == 1 && model.error == nil)
        #expect(await loader.requests.last?.completed == ["42/1"])
        #expect(await loader.requests.last?.page == nil)
    }

    @Test("Switching accounts while a response is in flight discards all old-account data")
    func accountSwitch() async throws {
        let context = try makeContext()
        let loader = GatedHistoryLoader()
        let model = WorkflowHistoryViewModel(loader: loader)
        try model.select(selection, in: context)
        let task = Task { await model.load(in: context, refresh: true) }
        await loader.waitForRequest()
        try model.select(WorkflowHistorySelection(accountID: 8, keychainAccountKey: "other", repository: "example/other"), in: context)
        await loader.release(try page())
        await task.value
        #expect(model.entries.isEmpty && !model.isLoading)
        #expect(try context.fetchCount(FetchDescriptor<JobRunEntity>()) == 0)
    }

    @Test("Cancellation and explicit invalidation each reject a late response", arguments: [true, false])
    func invalidatedResponse(cancelTask: Bool) async throws {
        let context = try makeContext()
        let loader = GatedHistoryLoader()
        let model = WorkflowHistoryViewModel(loader: loader)
        try model.select(selection, in: context)
        let task = Task { await model.load(in: context, refresh: true) }
        await loader.waitForRequest()
        if cancelTask { task.cancel() } else { model.invalidate() }
        await loader.release(try page())
        await task.value
        #expect(model.entries.isEmpty && !model.isLoading)
        #expect(try context.fetchCount(FetchDescriptor<JobRunEntity>()) == 0)
    }

    @Test("Stale pending snapshots never inflate live queue or concurrency counts")
    func staleQueue() throws {
        let context = try makeContext()
        let time = Date(timeIntervalSince1970: 1_800_000_000)
        let run = try JSONDecoder().decode(GitHubWorkflowRunDTO.self, from: Data(#"{"id":42,"status":"in_progress","run_attempt":1}"#.utf8))
        let entity = try WorkflowHistoryStore.upsert(run: run, jobs: [], repository: "example/repo", accountID: 7, observedAt: time, in: context)
        let entries = [WorkflowHistoryEntry(entity)]
        #expect(WorkflowHistoryMetrics(entries: entries, now: time).runningCount == 1)
        let later = WorkflowHistoryMetrics(entries: entries, now: time.addingTimeInterval(300))
        #expect(later.runningCount == 0 && later.stalePendingCount == 1)
    }

    @Test("Global refresh loads repository sources sequentially without mixing accounts")
    func globalRefresh() async throws {
        let context = try makeContext()
        let loader = HistoryPageQueue([try page(), try page()])
        let model = WorkflowHistoryViewModel(loader: loader)
        let second = WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture-account", repository: "example/second")
        await model.refreshRepositories([selection, second], in: context)
        #expect(model.entries.count == 2)
        #expect(Set(model.entries.map(\.repository)) == ["example/repo", "example/second"])
        #expect(await loader.requests.count == 2)
        await model.refreshRepositories([], in: context)
        #expect(model.entries.isEmpty)
        let foreign = WorkflowHistorySelection(accountID: 8, keychainAccountKey: "other-account", repository: "other/repo")
        await model.refreshRepositories([selection, foreign], in: context)
        #expect(model.entries.isEmpty)
        #expect(await loader.requests.count == 2)
    }

    @Test("Invalidation or cancellation interrupts global refresh before the next source", arguments: [true, false])
    func globalRefreshCancellation(cancelTask: Bool) async throws {
        let context = try makeContext()
        let loader = GatedHistoryLoader()
        let model = WorkflowHistoryViewModel(loader: loader)
        let second = WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture-account", repository: "example/second")
        let task = Task { await model.refreshRepositories([selection, second], in: context) }
        await loader.waitForRequest()
        if cancelTask { task.cancel() } else { model.invalidate() }
        await loader.release(try page())
        await task.value
        #expect(await loader.calls == 1)
        #expect(try context.fetchCount(FetchDescriptor<JobRunEntity>()) == 0)
    }

    @Test("An inaccessible repository cannot starve later sources; failures stay visible")
    func repositoryFailureIsolation() async throws {
        let context = try makeContext()
        let loader = ScriptedHistoryLoader([.failure(.permissionDenied), .success(try page())])
        let model = WorkflowHistoryViewModel(loader: loader)
        let second = WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture-account", repository: "example/second")
        await model.refreshRepositories([selection, second], in: context)
        #expect(await loader.calls == 2)
        #expect(model.entries.map(\.repository) == ["example/second"])
        #expect(model.repositoryFailures.map(\.repository) == ["example/repo"])
        #expect(model.repositoryFailures.first?.error == .permissionDenied)
        #expect(model.error == nil)
    }

    @Test("Global refresh stops on authentication and rate failures", arguments: [WorkflowHistoryLoadError.authenticationRequired, .rateLimited(until: nil)])
    func batchStopsForAccountFailures(error: WorkflowHistoryLoadError) async throws {
        let context = try makeContext()
        let loader = ScriptedHistoryLoader([.failure(error), .success(try page())])
        let model = WorkflowHistoryViewModel(loader: loader)
        let second = WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture-account", repository: "example/second")
        await model.refreshRepositories([selection, second], in: context)
        #expect(await loader.calls == 1)
        #expect(model.error == error)
        #expect(model.entries.isEmpty)
    }

    @Test("Account rate budgets survive replacing the history view model")
    func sharedRateBudget() async throws {
        let context = try makeContext()
        let deadline = Date.now.addingTimeInterval(300)
        let loader = ScriptedHistoryLoader([.failure(.rateLimited(until: deadline)), .success(try page())])
        let budget = WorkflowHistoryRateBudget()
        let first = WorkflowHistoryViewModel(loader: loader, rateBudget: budget)
        try first.select(selection, in: context)
        await first.load(in: context, refresh: true)
        let replacement = WorkflowHistoryViewModel(loader: loader, rateBudget: budget)
        try replacement.select(selection, in: context)
        await replacement.load(in: context, refresh: true)
        #expect(await loader.calls == 1)
        #expect(replacement.retryNotBefore == deadline)
    }

    private func makeContext() throws -> ModelContext {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        return container.mainContext
    }

    private func page() throws -> WorkflowHistoryPage {
        let run = try JSONDecoder().decode(GitHubWorkflowRunDTO.self, from: Data(#"{"id":42,"status":"queued","run_attempt":1}"#.utf8))
        return WorkflowHistoryPage(runs: [WorkflowRunDetails(run: run, jobs: [])], nextPage: nil, rateLimit: nil, observedAt: .now)
    }
}

private actor HistorySecrets: SecretReading {
    let value: String?
    init(value: String? = "synthetic-fixture") { self.value = value }
    func readSecret(account: String, category: String) async throws -> String? { value }
}

private actor HistoryHTTPFixture: GitHubActionsTransport {
    private var responses: [GitHubActionsHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ payloads: [String]) {
        responses = payloads.map { GitHubActionsHTTPResponse(statusCode: 200, headers: [:], data: Data($0.utf8)) }
    }
    init(responses: [GitHubActionsHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw WorkflowHistoryLoadError.unavailable }
        return responses.removeFirst()
    }
}

private actor HistoryPageQueue: WorkflowHistoryLoading {
    private var pages: [WorkflowHistoryPage]
    private(set) var requests: [(page: URL?, completed: Set<String>)] = []
    init(_ pages: [WorkflowHistoryPage]) { self.pages = pages }
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage {
        requests.append((nextPage, completedAttempts))
        guard !pages.isEmpty else { throw WorkflowHistoryLoadError.unavailable }
        return pages.removeFirst()
    }
}

private actor RateLimitedHistoryLoader: WorkflowHistoryLoading {
    let deadline: Date
    let result: WorkflowHistoryPage
    private(set) var calls = 0
    init(deadline: Date, result: WorkflowHistoryPage) { self.deadline = deadline; self.result = result }
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage {
        calls += 1
        if calls == 1 { throw WorkflowHistoryLoadError.rateLimited(until: deadline) }
        return result
    }
}

private actor GatedHistoryLoader: WorkflowHistoryLoading {
    private var response: CheckedContinuation<WorkflowHistoryPage, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private let subsequentError: WorkflowHistoryLoadError
    private(set) var calls = 0
    init(subsequentError: WorkflowHistoryLoadError = .unavailable) { self.subsequentError = subsequentError }
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage {
        calls += 1
        if calls > 1 { throw subsequentError }
        return try await withCheckedThrowingContinuation {
            response = $0
            started?.resume()
            started = nil
        }
    }
    func waitForRequest() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release(_ page: WorkflowHistoryPage) {
        response?.resume(returning: page)
        response = nil
    }
    func fail(_ error: WorkflowHistoryLoadError) {
        response?.resume(throwing: error)
        response = nil
    }
}

private actor ScriptedHistoryLoader: WorkflowHistoryLoading {
    var responses: [Result<WorkflowHistoryPage, WorkflowHistoryLoadError>]
    private(set) var calls = 0
    init(_ responses: [Result<WorkflowHistoryPage, WorkflowHistoryLoadError>]) { self.responses = responses }
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage {
        calls += 1
        guard !responses.isEmpty else { throw WorkflowHistoryLoadError.unavailable }
        return try responses.removeFirst().get()
    }
}
