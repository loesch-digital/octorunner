import CoreModels
import Foundation
import GitHubAPI
import DesignSystem
import SecurityKit
import SwiftData
import SwiftUI
import AppKit
import Testing
@testable import AppShellFeature

@MainActor
struct WorkflowRunDetailTests {
    @Test("Job steps decode independent states and only measured completed durations")
    func steps() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let job = try decoder.decode(GitHubWorkflowJobDTO.self, from: Data(#"{"id":100,"run_id":42,"name":"Build","status":"in_progress","steps":[{"number":1,"name":"Checkout","status":"completed","conclusion":"success","started_at":"2026-11-19T10:00:00Z","completed_at":"2026-11-19T10:00:03Z"},{"number":2,"name":"Test","status":"in_progress","conclusion":null,"started_at":"2026-11-19T10:00:03Z"},{"number":3,"name":"Upload","status":"queued"}]}"#.utf8))
        #expect(job.steps?.map(\.number) == [1, 2, 3])
        #expect(job.steps?.first?.snapshot.durationSeconds == 3)
        #expect(job.steps?.last?.snapshot.durationSeconds == nil)
        #expect(job.steps?[1].snapshot.durationSeconds == nil)
        let failure = WorkflowJobStep(number: 1, name: "Test", status: "completed", conclusion: "failure", startedAt: nil, completedAt: nil)
        #expect(WorkflowStepPresentation(step: failure, locale: Locale(identifier: "en")).symbol == "xmark.circle.fill")
        for (conclusion, symbol) in [("skipped", "forward.end"), ("cancelled", "slash.circle"), ("success", "checkmark.circle.fill"), ("other", "checkmark.circle")] {
            let step = WorkflowJobStep(number: 1, name: "Step", status: "completed", conclusion: conclusion, startedAt: nil, completedAt: nil)
            #expect(WorkflowStepPresentation(step: step, locale: Locale(identifier: "en")).symbol == symbol)
        }
    }

    @Test("Details load exactly the selected attempt and retain null step lists as unknown")
    func selectedAttempt() async throws {
        let transport = DetailHTTPFixture()
        let model = WorkflowRunDetailModel(client: GitHubActionsClient(transport: transport), secrets: DetailSecrets())
        model.select(selection(attempt: 2))
        await model.load()
        #expect(model.jobs.map(\.id) == [100])
        #expect(model.jobs.first?.steps == nil)
        #expect(model.observedAt != nil && model.error == nil && !model.isLoading)
        #expect(await transport.requests.last?.url?.path == "/repos/example/repo/actions/runs/42/attempts/2/jobs")
    }

    @Test("Invalidation, account switching and cancellation discard late detail responses", arguments: [0, 1, 2])
    func lateDetails(_ change: Int) async {
        let transport = DetailHTTPFixture(gated: true)
        let model = WorkflowRunDetailModel(client: GitHubActionsClient(transport: transport), secrets: DetailSecrets())
        model.select(selection(attempt: 1))
        let task = Task { await model.load() }
        await transport.waitForRequest()
        if change == 0 { model.invalidate() }
        if change == 1 { model.select(.init(source: .init(accountID: 8, keychainAccountKey: "other", repository: "example/repo"), runID: 42, attempt: 1)) }
        if change == 2 { task.cancel() }
        await transport.release()
        await task.value
        #expect(model.jobs.isEmpty && model.observedAt == nil && model.error == nil && !model.isLoading)
    }

    @Test("Permission, missing logs and API limits remain distinguishable in detail requests", arguments: [403, 404, 429])
    func requestFailure(_ status: Int) async {
        let transport = DetailHTTPFixture(status: status)
        let budget = WorkflowHistoryRateBudget()
        let model = WorkflowRunDetailModel(client: GitHubActionsClient(transport: transport), secrets: DetailSecrets(), rateBudget: budget)
        model.select(selection(attempt: 1))
        await model.load()
        #expect(model.error != nil && model.jobs.isEmpty && model.observedAt == nil)
        if status == 429 { #expect(budget.deadline(for: 7) != nil) }
    }

    @Test("Step snapshots persist independently for each job and missing data stays unknown")
    func stepPersistence() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let run = try JSONDecoder().decode(GitHubWorkflowRunDTO.self, from: Data(#"{"id":42,"run_attempt":1}"#.utf8))
        let job = try JSONDecoder().decode(GitHubWorkflowJobDTO.self, from: Data(#"{"id":100,"run_id":42,"name":"Build","status":"completed","steps":[{"number":1,"name":"Test","status":"completed","conclusion":"failure"}]}"#.utf8))
        try WorkflowHistoryStore.upsert(run: run, jobs: [job], repository: "example/repo", accountID: 7, in: container.mainContext)
        let records = try ModelContext(container).fetch(FetchDescriptor<JobRunEntity>()).map(WorkflowHistoryEntry.init)
        #expect(records.first { $0.githubJobID == 100 }?.steps?.first?.conclusion == "failure")
        #expect(records.first { $0.githubJobID == nil }?.steps == nil)
    }

    @Test("Actions details render narrow and wide with long steps in both languages and appearances")
    func rendering() async throws {
        let entity = JobRunEntity(githubRunId: 42, workflowName: String(repeating: "Workflow ", count: 15), repositoryFullName: "example/repo", branchName: "feature", commitSha: "abcdef")
        entity.runAttempt = 2
        let model = WorkflowRunDetailModel(client: GitHubActionsClient(transport: DetailHTTPFixture(withSteps: true)), secrets: DetailSecrets())
        for width in [620.0, 960.0] {
            for language in ["de", "en"] {
                for scheme in [ColorScheme.light, .dark] {
                    let host = NSHostingView(rootView: WorkflowRunDetailView(entry: WorkflowHistoryEntry(entity), selection: selection(attempt: 2), model: model)
                        .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme).frame(width: width, height: 620))
                    host.frame = CGRect(x: 0, y: 0, width: width, height: 620)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false; window.contentView = host
                    for _ in 0..<10 { await Task.yield() }
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                        try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(filePath: path).appending(path: "workflow-details-\(language)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                    }
                    window.contentView = nil; window.close()
                }
            }
        }
    }

    @Test("Opening details requires the active account, repository and a known attempt")
    func openingSelection() {
        let entity = JobRunEntity(githubRunId: 42, workflowName: "CI", repositoryFullName: "example/repo", branchName: "feature", commitSha: "sha")
        entity.accountGitHubUserID = 7
        let source = WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture", repository: "example/repo")
        #expect(WorkflowRunDetailSelection(entry: WorkflowHistoryEntry(entity), source: source) == nil)
        entity.runAttempt = 2
        #expect(WorkflowRunDetailSelection(entry: WorkflowHistoryEntry(entity), source: source)?.attempt == 2)
        entity.accountGitHubUserID = 8
        #expect(WorkflowRunDetailSelection(entry: WorkflowHistoryEntry(entity), source: source) == nil)
    }

    @Test("Detail controls are translated into German")
    func localization() {
        #expect(AppLocalization.string("View workflow details", locale: Locale(identifier: "de")) == "Workflow-Details anzeigen")
        #expect(AppLocalization.string("Step details unavailable", locale: Locale(identifier: "de")) == "Step-Details nicht verfügbar")
        #expect(AppLocalization.string("Open job on GitHub", locale: Locale(identifier: "de")) == "Job auf GitHub öffnen")
    }

    @Test("Duplicate or nonpositive step numbers are rejected before rendering", arguments: ["0", "1"])
    func invalidSteps(_ second: String) async throws {
        let payload = "{\"total_count\":1,\"jobs\":[{\"id\":100,\"run_id\":42,\"name\":\"Build\",\"status\":\"queued\",\"steps\":[{\"number\":1,\"name\":\"One\",\"status\":\"queued\"},{\"number\":\(second),\"name\":\"Two\",\"status\":\"queued\"}]}]}"
        let transport = InvalidStepTransport(payload: payload)
        let client = GitHubActionsClient(transport: transport)
        await #expect(throws: GitHubActionsError.invalidResponse) {
            try await client.workflowJobs(repository: "example/repo", runID: 42, attempt: 1, token: "fixture")
        }
    }

    @Test("Partial or cyclic detail pages never appear as a complete job list", arguments: [false, true])
    func incompletePages(_ cycle: Bool) async {
        let path = "https://api.github.com/repos/example/repo/actions/runs/42/attempts/2/jobs?page=2&per_page=100"
        let transport = DetailHTTPFixture(headers: cycle ? ["Link": "<\(path)>; rel=\"next\""] : [:], totalCount: 2)
        let model = WorkflowRunDetailModel(client: GitHubActionsClient(transport: transport), secrets: DetailSecrets())
        model.select(selection(attempt: 2))
        await model.load()
        #expect(model.error != nil && model.jobs.isEmpty && model.observedAt == nil)
    }

    @Test("Explicit mismatched job attempts are rejected before display and persistence")
    func mismatchedAttempt() async throws {
        let payload = #"{"total_count":1,"jobs":[{"id":100,"run_id":42,"run_attempt":1,"name":"Wrong attempt","status":"completed"}]}"#
        let client = GitHubActionsClient(transport: InvalidStepTransport(payload: payload))
        await #expect(throws: GitHubActionsError.invalidResponse) {
            try await client.workflowJobs(repository: "example/repo", runID: 42, attempt: 2, token: "synthetic")
        }
        let run = try JSONDecoder().decode(GitHubWorkflowRunDTO.self, from: Data(#"{"id":42,"run_attempt":2,"status":"completed"}"#.utf8))
        let job = try JSONDecoder().decode(GitHubWorkflowJobDTO.self, from: Data(#"{"id":100,"run_id":42,"run_attempt":1,"name":"Wrong attempt","status":"completed"}"#.utf8))
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        #expect(throws: WorkflowHistoryError.inconsistentPayload) {
            try WorkflowHistoryStore.upsert(run: run, jobs: [job], repository: "example/repo", accountID: 7, in: container.mainContext)
        }
    }

    @Test("Workflow state keeps queued and between-stage details refreshing", arguments: ["queued", "in_progress", "completed"])
    func workflowRefresh(_ status: String) async {
        let fixture = DetailHTTPFixture(totalCount: 0, workflowStatus: status, emptyJobs: true)
        let model = WorkflowRunDetailModel(client: .init(transport: fixture), secrets: DetailSecrets())
        model.select(selection(attempt: 2))
        await model.load()
        #expect(model.error == nil && model.jobs.isEmpty)
        #expect(model.workflow?.status == status)
        #expect(model.shouldRefresh == (status != "completed"))
        #expect(await fixture.requests.first?.url?.path == "/repos/example/repo/actions/runs/42/attempts/2")
    }

    @Test("Job and step status use the same semantic blue for running")
    func statusColors() {
        let step = WorkflowJobStep(number: 1, name: "Build", status: "in_progress", conclusion: nil, startedAt: nil, completedAt: nil)
        #expect(WorkflowStepPresentation(step: step, locale: Locale(identifier: "en")).color == OctoTheme.accentBlue)
    }

    private func selection(attempt: Int) -> WorkflowRunDetailSelection {
        .init(source: .init(accountID: 7, keychainAccountKey: "fixture", repository: "example/repo"), runID: 42, attempt: attempt)
    }
}

private struct DetailSecrets: SecretReading {
    func readSecret(account: String, category: String) async -> String? { "fixture-token" }
}

private actor DetailHTTPFixture: GitHubActionsTransport {
    let gated: Bool
    let status: Int
    let withSteps: Bool
    let headers: [String: String]
    let totalCount: Int
    let workflowStatus: String
    let emptyJobs: Bool
    private let started = AsyncStream<Void>.makeStream()
    private var pending: CheckedContinuation<Void, Never>?
    private(set) var requests: [URLRequest] = []
    init(gated: Bool = false, status: Int = 200, withSteps: Bool = false, headers: [String: String] = [:], totalCount: Int = 1, workflowStatus: String = "in_progress", emptyJobs: Bool = false) { self.gated = gated; self.status = status; self.withSteps = withSteps; self.headers = headers; self.totalCount = totalCount; self.workflowStatus = workflowStatus; self.emptyJobs = emptyJobs }
    func send(_ request: URLRequest) async -> GitHubActionsHTTPResponse {
        requests.append(request)
        if gated && requests.count == 1 {
            await withCheckedContinuation { pending = $0; started.continuation.yield(()); started.continuation.finish() }
        }
        if request.url?.path.hasSuffix("/jobs") != true {
            return .init(statusCode: status, headers: headers, data: Data("{\"id\":42,\"run_attempt\":2,\"status\":\"\(workflowStatus)\"}".utf8))
        }
        if emptyJobs { return .init(statusCode: status, headers: headers, data: Data(#"{"total_count":0,"jobs":[]}"#.utf8)) }
        let steps = withSteps ? ",\"steps\":[{\"number\":1,\"name\":\"Build and test a long workflow step with a deliberately descriptive name\",\"status\":\"completed\",\"conclusion\":\"failure\"},{\"number\":2,\"name\":\"Upload diagnostics\",\"status\":\"in_progress\"}]" : ""
        return .init(statusCode: status, headers: headers, data: Data("{\"total_count\":\(totalCount),\"jobs\":[{\"id\":100,\"run_id\":42,\"name\":\"Build\",\"status\":\"\(withSteps ? "in_progress" : "queued")\"\(steps)}]}".utf8))
    }
    func waitForRequest() async { for await _ in started.stream { break } }
    func release() { pending?.resume(); pending = nil }
}

private struct InvalidStepTransport: GitHubActionsTransport {
    let payload: String
    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        .init(statusCode: 200, headers: [:], data: Data(payload.utf8))
    }
}
