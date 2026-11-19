import AppKit
@testable import AppShellFeature
import CoreModels
import Foundation
import GitHubAPI
import SwiftData
import SwiftUI
import Testing
import SecurityKit

@MainActor
struct WorkflowPullRequestTests {
    @Test("Pull request references use the base repository, not a fork head, and preserve unknown metadata")
    func decoding() throws {
        let run = try decode(#"[{"number":12,"base":{"repo":{"url":"https://api.github.com/repos/example/repo"}},"head":{"repo":{"url":"https://api.github.com/repos/fork/repo"}}}]"#)
        #expect(run.pullRequests?.first?.number == 12)
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let record = try WorkflowHistoryStore.upsert(run: run, jobs: [], repository: "example/repo", accountID: 7, in: container.mainContext)
        let reference = try #require(WorkflowHistoryEntry(record).pullRequests?.first)
        #expect(reference.repository == "example/repo" && reference.number == 12)
        #expect(reference.url.absoluteString == "https://github.com/example/repo/pull/12")
        #expect(try decode(nil).pullRequests == nil)
        #expect(try decode("[]").pullRequests == [])
    }

    @Test("Wrong repositories, invalid numbers and untrusted base URLs cannot create PR links", arguments: [
        #"{"number":-1,"base":{"repo":{"url":"https://api.github.com/repos/example/repo"}}}"#,
        #"{"number":12,"base":{"repo":{"url":"https://evil.example/repos/example/repo"}}}"#,
        #"{"number":12,"base":{"repo":{"url":"https://api.github.com/repos/other/repo"}}}"#,
        #"{"number":12,"base":{"repo":{"url":"https://user@api.github.com/repos/example/repo"}}}"#,
        #"{"number":12,"base":{"repo":{"url":"https://api.github.com/repos/example/repo?x=1"}}}"#
    ])
    func unsafeReferences(_ json: String) throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let record = try WorkflowHistoryStore.upsert(run: decode("[\(json)]"), jobs: [], repository: "example/repo", accountID: 7, in: container.mainContext)
        #expect(WorkflowHistoryEntry(record).pullRequests?.isEmpty == true)
    }

    @Test("PR references survive a fresh context and stay isolated by account and run attempt")
    func persistenceAndSearch() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let run = try decode(#"[{"number":12,"base":{"repo":{"url":"https://api.github.com/repos/example/repo"}}},{"number":14,"base":{"repo":{"url":"https://api.github.com/repos/example/repo"}}}]"#)
        let first = try WorkflowHistoryStore.upsert(run: run, jobs: [], repository: "example/repo", accountID: 7, in: container.mainContext)
        let identity = first.id
        _ = try WorkflowHistoryStore.upsert(run: decode(nil), jobs: [], repository: "example/repo", accountID: 8, in: container.mainContext)
        let context = ModelContext(container)
        let entries = try context.fetch(FetchDescriptor<JobRunEntity>()).map(WorkflowHistoryEntry.init)
        #expect(entries.first { $0.id == identity }?.pullRequests?.map(\.number) == [12, 14])
        #expect(WorkflowHistoryFilter(accountID: 7, search: "#12").apply(to: entries).count == 1)
        #expect(WorkflowHistoryFilter(accountID: 8, search: "#12").apply(to: entries).isEmpty)
        // Missing data on refresh must not erase a known association.
        _ = try WorkflowHistoryStore.upsert(run: decode(nil), jobs: [], repository: "example/repo", accountID: 7, in: container.mainContext)
        #expect(WorkflowHistoryEntry(first).pullRequests?.map(\.number) == [12, 14])
    }

    @Test("Persisted PR metadata is revalidated rather than trusting decoded data")
    func untrustedStoredReferences() throws {
        let entity = JobRunEntity(githubRunId: 42, workflowName: "CI", repositoryFullName: "example/repo", branchName: "feature", commitSha: "sha")
        entity.pullRequestReferencesData = Data(#"[{"number":12,"repository":"other/repo"}]"#.utf8)
        #expect(WorkflowHistoryEntry(entity).pullRequests?.isEmpty == true)
        entity.pullRequestReferencesData = Data("not JSON".utf8)
        #expect(WorkflowHistoryEntry(entity).pullRequests == nil)
    }

    @Test("A PR event with empty run metadata resolves the commit association without extra write permissions")
    func fallbackLookup() async throws {
        let sha = String(repeating: "a", count: 40)
        let transport = PullRequestTransport([
            .init(statusCode: 200, headers: [:], data: Data("{\"total_count\":1,\"workflow_runs\":[{\"id\":42,\"run_attempt\":1,\"event\":\"pull_request\",\"head_sha\":\"\(sha)\",\"pull_requests\":[]}] }".utf8)),
            .init(statusCode: 200, headers: [:], data: Data(#"[{"number":12,"base":{"repo":{"url":"https://api.github.com/repos/example/repo"}}}]"#.utf8)),
            .init(statusCode: 200, headers: [:], data: Data(#"{"total_count":0,"jobs":[]}"#.utf8))
        ])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: PullRequestSecrets())
        let page = try await loader.page(selection: .init(accountID: 7, keychainAccountKey: "fixture", repository: "example/repo"), nextPage: nil, completedAttempts: [])
        #expect(page.runs.first?.run.pullRequests?.first?.number == 12)
        let requests = await transport.requests
        #expect(requests.map { $0.httpMethod } == ["GET", "GET", "GET"])
        #expect(requests.dropFirst().first?.url?.path == "/repos/example/repo/commits/\(sha)/pulls")
    }

    @Test("PR lookup permission failure keeps Actions history usable and marks PR data unknown")
    func fallbackPermission() async throws {
        let sha = String(repeating: "b", count: 40)
        let transport = PullRequestTransport([
            .init(statusCode: 200, headers: [:], data: Data("{\"total_count\":1,\"workflow_runs\":[{\"id\":42,\"run_attempt\":1,\"event\":\"pull_request\",\"head_sha\":\"\(sha)\",\"pull_requests\":[]}] }".utf8)),
            .init(statusCode: 403, headers: [:], data: Data()),
            .init(statusCode: 200, headers: [:], data: Data(#"{"total_count":0,"jobs":[]}"#.utf8))
        ])
        let loader = GitHubWorkflowHistoryLoader(client: GitHubActionsClient(transport: transport), secrets: PullRequestSecrets())
        let page = try await loader.page(selection: .init(accountID: 7, keychainAccountKey: "fixture", repository: "example/repo"), nextPage: nil, completedAttempts: [])
        #expect(page.runs.count == 1 && page.runs.first?.run.pullRequests == nil)
    }

    @Test("Commit lookup rejects path injection before reading credentials", arguments: ["", "main", "../pulls", String(repeating: "a", count: 39), String(repeating: "g", count: 40)])
    func invalidCommit(_ sha: String) async {
        let transport = PullRequestTransport([])
        let client = GitHubActionsClient(transport: transport)
        await #expect(throws: GitHubActionsError.invalidResponse) {
            try await client.pullRequests(repository: "example/repo", commitSHA: sha, token: "fixture-token")
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("PR links remain readable with long metadata in narrow and wide DE/EN appearances")
    func rendering() throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let entity = try WorkflowHistoryStore.upsert(run: decode(#"[{"number":12,"base":{"repo":{"url":"https://api.github.com/repos/example/repo"}}}]"#), jobs: [], repository: "example/repo", accountID: 7, in: container.mainContext)
        for width in [560.0, 960.0] {
            for language in ["de", "en"] {
                for scheme in [ColorScheme.light, .dark] {
                    let host = NSHostingView(rootView: WorkflowPullRequestLinksView(entry: WorkflowHistoryEntry(entity))
                        .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme)
                        .padding().frame(width: width))
                    host.frame = CGRect(x: 0, y: 0, width: width, height: 180)
                    host.layoutSubtreeIfNeeded()
                    #expect(host.fittingSize.height <= 180)
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                }
            }
        }
    }

    @Test("Invalid serialized references cannot bypass validated construction")
    func invalidSerializedReference() {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(WorkflowPullRequestReference.self, from: Data(#"{"number":-1,"repository":"example/repo"}"#.utf8))
        }
    }

    @Test("PR context has German copy and the search field advertises PR search")
    func localization() {
        #expect(AppLocalization.string("Pull request details unavailable", locale: Locale(identifier: "de")) == "Pull-Request-Details nicht verfügbar")
        #expect(AppLocalization.string("Workflow, branch, commit or PR", locale: Locale(identifier: "de")) == "Workflow, Branch, Commit oder PR")
    }

    private func decode(_ references: String?) throws -> GitHubWorkflowRunDTO {
        let property = references.map { ",\"pull_requests\":\($0)" } ?? ""
        return try JSONDecoder().decode(GitHubWorkflowRunDTO.self,
            from: Data("{\"id\":42,\"run_attempt\":1,\"event\":\"pull_request\"\(property)}".utf8))
    }
}

private actor PullRequestTransport: GitHubActionsTransport {
    var responses: [GitHubActionsHTTPResponse]
    private(set) var requests: [URLRequest] = []
    init(_ responses: [GitHubActionsHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest) throws -> GitHubActionsHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else { throw URLError(.badServerResponse) }
        return responses.removeFirst()
    }
}

private struct PullRequestSecrets: SecretReading {
    func readSecret(account: String, category: String) async -> String? { "fixture-token" }
}
