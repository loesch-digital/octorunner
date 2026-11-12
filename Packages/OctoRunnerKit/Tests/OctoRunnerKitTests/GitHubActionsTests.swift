import Foundation
import GitHubAPI
import Testing

struct GitHubActionsTests {
    @Test("Nullable run status and an omitted attempt remain unknown rather than failing the page")
    func unknownRunMetadata() async throws {
        let payload = #"{"total_count":1,"workflow_runs":[{"id":42,"name":"CI","status":null,"conclusion":null}]}"#
        let transport = ActionsFixtureTransport([GitHubActionsHTTPResponse(statusCode: 200, headers: [:], data: Data(payload.utf8))])
        let page = try await GitHubActionsClient(transport: transport).workflowRuns(repository: "example/repo", token: "fixture-token")
        #expect(page.items.count == 1)
        #expect(page.items.first?.status == nil)
        #expect(page.items.first?.runAttempt == nil)
    }

    @Test("Malformed credentials cannot become HTTP headers", arguments: ["", "fixture token", "fixture\nvalue", "fixture\u{0000}value"])
    func invalidTokens(_ token: String) async {
        let transport = ActionsFixtureTransport([])
        let client = GitHubActionsClient(transport: transport)
        await #expect(throws: GitHubActionsError.invalidToken) { try await client.workflowRuns(repository: "example/repo", token: token) }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Production URLSession delegate rejects redirects even to another GitHub repository")
    func redirects() async throws {
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = try #require(URL(string: "https://api.github.com/repos/example/repo/actions/runs"))
        let response = try #require(HTTPURLResponse(url: original, statusCode: 301, httpVersion: nil, headerFields: nil))
        let task = session.dataTask(with: original)
        defer { task.cancel() }
        for target in ["https://evil.example/", "https://api.github.com/repos/other/repo/actions/runs"] {
            let request = URLRequest(url: try #require(URL(string: target)))
            #expect(await GitHubActionsRedirectDelegate().urlSession(session, task: task, willPerformHTTPRedirection: response, newRequest: request) == nil)
        }
    }

    @Test("A cancelled request rejects late data before recording rate limits")
    func lateCancelledResponse() async throws {
        let transport = GatedActionsTransport()
        let client = GitHubActionsClient(transport: transport)
        let task = Task { try await client.workflowRuns(repository: "example/repo", token: "fixture-token") }
        await transport.waitForRequest()
        task.cancel()
        await transport.release(GitHubActionsHTTPResponse(statusCode: 200, headers: ["X-RateLimit-Remaining": "42"], data: Data(Self.runsJSON.utf8)))
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await client.rateLimit == nil)
    }

    @Test("Runs pagination uses only the requested repository and current read-only API")
    func paginatedRuns() async throws {
        let next = "https://api.github.com/repos/example/repo/actions/runs?per_page=100&page=2"
        let transport = ActionsFixtureTransport([
            GitHubActionsHTTPResponse(statusCode: 200, headers: ["Link": "<\(next)>; rel=\"next\"", "X-RateLimit-Limit": "5000", "X-RateLimit-Remaining": "4999", "X-RateLimit-Reset": "2000000000"], data: Data(Self.runsJSON.utf8)),
            GitHubActionsHTTPResponse(statusCode: 200, headers: [:], data: Data(#"{"total_count":1,"workflow_runs":[]}"#.utf8))
        ])
        let client = GitHubActionsClient(transport: transport)
        let first = try await client.workflowRuns(repository: "example/repo", token: "fixture-token")
        #expect(first.items.count == 1)
        #expect(first.items.first?.runAttempt == 2)
        #expect(first.items.first?.conclusion == nil)
        #expect(first.items.first?.startedAt != nil)
        #expect(first.nextPage?.absoluteString == next)
        #expect(first.rateLimit?.remaining == 4999)
        let second = try await client.workflowRuns(repository: "example/repo", token: "fixture-token", page: first.nextPage)
        #expect(second.items.isEmpty && second.nextPage == nil)
        #expect(second.rateLimit == nil)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.allSatisfy { $0.httpMethod == "GET" && $0.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-token" })
        #expect(requests.first?.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        #expect(await client.rateLimit?.remaining == 4999)
    }

    @Test("Jobs use the explicit attempt and decode queued jobs without invented timestamps or runner assignments")
    func workflowJobs() async throws {
        let payload = #"{"total_count":2,"jobs":[{"id":10,"run_id":42,"name":"build","status":"queued","conclusion":null,"started_at":null,"completed_at":null,"runner_id":null,"runner_name":null,"labels":["self-hosted"]},{"id":11,"run_id":42,"name":"test","status":"completed","conclusion":"failure","started_at":"2026-11-12T05:00:00.123Z","completed_at":"2026-11-12T05:01:00Z","runner_id":99,"runner_name":"local"}]}"#
        let transport = ActionsFixtureTransport([GitHubActionsHTTPResponse(statusCode: 200, headers: [:], data: Data(payload.utf8))])
        let client = GitHubActionsClient(transport: transport)
        let jobs = try await client.workflowJobs(repository: "example/repo", runID: 42, attempt: 2, token: "fixture-token")
        #expect(jobs.items.count == 2)
        #expect(jobs.items.first?.startedAt == nil && jobs.items.first?.runnerID == nil)
        #expect(jobs.items.last?.conclusion == "failure")
        #expect(jobs.items.last?.startedAt != nil)
        #expect(await transport.requests.first?.url?.path == "/repos/example/repo/actions/runs/42/attempts/2/jobs")
    }

    @Test("Untrusted pagination cannot receive a credential", arguments: [
        "https://evil.example/repos/example/repo/actions/runs?page=2",
        "http://api.github.com/repos/example/repo/actions/runs?page=2",
        "https://api.github.com/repos/other/repo/actions/runs?page=2",
        "https://api.github.com:8443/repos/example/repo/actions/runs?page=2",
        "https://user@api.github.com/repos/example/repo/actions/runs?page=2",
        "https://api.github.com/repos/example/repo/actions/runs?page=2&page=3"
    ])
    func unsafePagination(_ next: String) async throws {
        let transport = ActionsFixtureTransport([GitHubActionsHTTPResponse(statusCode: 200, headers: ["Link": "<\(next)>; rel=\"next\""], data: Data(Self.runsJSON.utf8))])
        let client = GitHubActionsClient(transport: transport)
        await #expect(throws: GitHubActionsError.invalidPagination) {
            try await client.workflowRuns(repository: "example/repo", token: "fixture-token")
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("Invalid repository names are rejected before a network request", arguments: ["../repo", "example/repo/extra", "example/repo?token=x", "https://github.com/example/repo", "example/%2e%2e"])
    func invalidRepository(_ repository: String) async {
        let transport = ActionsFixtureTransport([])
        let client = GitHubActionsClient(transport: transport)
        await #expect(throws: GitHubActionsError.invalidRepository) { try await client.workflowRuns(repository: repository, token: "fixture-token") }
        #expect(await transport.requests.isEmpty)
    }

    @Test("HTTP failures retain rate-limit metadata but never return reflected response bodies", arguments: [401, 403, 429])
    func httpErrors(_ status: Int) async {
        let transport = ActionsFixtureTransport([GitHubActionsHTTPResponse(statusCode: status, headers: ["X-RateLimit-Limit": "5000", "X-RateLimit-Remaining": "0", "Retry-After": "60"], data: Data("reflected fixture-token".utf8))])
        let client = GitHubActionsClient(transport: transport)
        do {
            _ = try await client.workflowRuns(repository: "example/repo", token: "fixture-token")
            Issue.record("Expected an HTTP failure")
        } catch GitHubActionsError.httpStatus(let receivedStatus, let rate) {
            #expect(receivedStatus == status)
            #expect(rate?.remaining == 0 && rate?.retryAfterSeconds == 60)
        } catch { Issue.record("Expected a typed HTTP status error") }
        #expect(await client.rateLimit?.remaining == 0)
        #expect(await client.rateLimit?.retryAfterSeconds == 60)
    }

    private static let runsJSON = #"{"total_count":1,"workflow_runs":[{"id":42,"name":"CI","head_branch":"main","head_sha":"abcdef","status":"in_progress","conclusion":null,"run_attempt":2,"created_at":"2026-11-12T04:59:00Z","run_started_at":"2026-11-12T05:00:00Z","updated_at":"2026-11-12T05:00:01Z","event":"push","html_url":"https://github.com/example/repo/actions/runs/42"}]}"#
}

private actor GatedActionsTransport: GitHubActionsTransport {
    private let started = AsyncStream<Void>.makeStream()
    private var continuation: CheckedContinuation<GitHubActionsHTTPResponse, Never>?
    func send(_ request: URLRequest) async -> GitHubActionsHTTPResponse {
        started.continuation.yield(())
        return await withCheckedContinuation { continuation = $0 }
    }
    func waitForRequest() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
    func release(_ response: GitHubActionsHTTPResponse) {
        continuation?.resume(returning: response)
        continuation = nil
    }
}

private actor ActionsFixtureTransport: GitHubActionsTransport {
    private var responses: [GitHubActionsHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [GitHubActionsHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> GitHubActionsHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}
