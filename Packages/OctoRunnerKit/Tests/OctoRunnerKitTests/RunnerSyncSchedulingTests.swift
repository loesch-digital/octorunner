@testable import AppShellFeature
import CoreModels
import Foundation
import GitHubAPI
import SyncKit
import Testing

struct RunnerSyncSchedulingTests {
    @Test("Runner lookup keeps authentication failures, missing runners and service failures distinct")
    func classifiesResponses() async throws {
        let cases: [(Int, RunnerLookupResult)] = [
            (304, .notModified), (401, .unauthorized), (403, .forbidden),
            (404, .notFound), (503, .unavailable)
        ]
        let config = try configuration()
        for (status, result) in cases {
            let sync = GitHubRunnerSyncActor(transport: RunnerSyncTestTransport { request in
                #expect(request.url?.absoluteString == "https://api.github.com/repos/example/build/actions/runners/21")
                #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
                #expect(request.value(forHTTPHeaderField: "If-None-Match") == "fixture-etag")
                return .init(statusCode: status, headers: [:], data: Data())
            })
            #expect(try await sync.lookupRunner(for: config, token: "fixture-token", eTag: "fixture-etag") == result)
        }
    }

    @Test("A rate-limited runner lookup honors Retry-After", arguments: [403, 429])
    func retryAfter(_ status: Int) async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let sync = GitHubRunnerSyncActor(transport: RunnerSyncTestTransport { _ in
            .init(statusCode: status, headers: ["Retry-After": "120"], data: Data())
        })
        #expect(try await sync.lookupRunner(for: configuration(), token: "fixture-token", now: now)
                == .rateLimited(retryAt: now.addingTimeInterval(120)))
    }

    @Test("An exhausted quota with no valid reset uses a conservative backoff")
    func rateLimitWithoutReset() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let sync = GitHubRunnerSyncActor(transport: RunnerSyncTestTransport { _ in
            .init(statusCode: 403, headers: ["X-RateLimit-Remaining": "0"], data: Data())
        })
        #expect(try await sync.lookupRunner(for: configuration(), token: "fixture-token", now: now)
                == .rateLimited(retryAt: now.addingTimeInterval(60)))
    }

    @Test("A secondary limit uses backoff even when the primary quota is available")
    func headerlessSecondaryLimit() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let sync = GitHubRunnerSyncActor(transport: RunnerSyncTestTransport { _ in
            let data = Data(#"{"message":"You have exceeded a secondary rate limit."}"#.utf8)
            return .init(statusCode: 403, headers: ["X-RateLimit-Remaining": "300"], data: data)
        })
        #expect(try await sync.lookupRunner(for: configuration(), token: "fixture-token", now: now)
                == .rateLimited(retryAt: now.addingTimeInterval(60)))
    }

    @Test("A 200 response must identify the requested runner and can provide an ETag", arguments: [21, 22])
    func verifiesRunnerIdentity(_ id: Int) async throws {
        let json = """
        {"id":\(id),"name":"local","os":"macOS","status":"online","busy":true,"labels":[]}
        """
        let sync = GitHubRunnerSyncActor(transport: RunnerSyncTestTransport { _ in
            .init(statusCode: 200, headers: ["ETag": "fixture-etag"], data: Data(json.utf8))
        })
        let result = try await sync.lookupRunner(for: configuration(), token: "fixture-token")
        if id == 21 {
            guard case .found(let runner, let eTag) = result else {
                Issue.record("Expected a verified runner observation")
                return
            }
            #expect(runner.id == 21)
            #expect(runner.busy)
            #expect(eTag == "fixture-etag")
        } else {
            #expect(result == .unavailable)
        }
    }

    @Test("An unsupported scope never sends a request", arguments: [
        "https://example.com/example/build", "https://github.com/example/build/extra",
        "https://github.com/example%2fother/build", "https://github.com/example/../build"
    ])
    func rejectsUnsupportedScope(_ url: String) async throws {
        let sync = GitHubRunnerSyncActor(transport: RunnerSyncTestTransport { _ in
            Issue.record("An unvalidated scope reached the transport")
            return .init(statusCode: 200, headers: [:], data: Data())
        })
        #expect(try await sync.lookupRunner(for: configuration(url), token: "fixture-token") == .unavailable)
    }

    @Test("Scope inventory follows every page and separates an empty list from insufficient evidence", arguments: [
        "complete", "duplicate", "changed-count", "denied", "empty", "organization", "exhausted", "continuation", "last-quota"
    ])
    func verifiesScopeInventory(_ scenario: String) async throws {
        let sync = GitHubRunnerSyncActor(transport: RunnerSyncTestTransport { request in
            let url = try #require(request.url)
            let expectedPath = scenario == "organization" ? "/orgs/example/actions/runners" : "/repos/example/build/actions/runners"
            #expect(url.path == expectedPath)
            #expect(url.query()?.contains("per_page=100") == true)
            #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
            let second = url.query()?.hasSuffix("page=2") == true
            if scenario == "continuation" {
                return .init(statusCode: 200, headers: ["Link": #"<https://api.github.com/other>; rel="next""#],
                    data: Data(#"{"total_count":0,"runners":[]}"#.utf8))
            }
            if scenario == "last-quota" {
                return .init(statusCode: 200, headers: ["X-RateLimit-Remaining": "0"],
                    data: Data(#"{"total_count":0,"runners":[]}"#.utf8))
            }
            if scenario == "denied", second {
                return .init(statusCode: 404, headers: [:], data: Data())
            }
            let ids = scenario == "empty" ? [] : second
                ? [scenario == "duplicate" ? 100 : 101]
                : Array(1...100)
            if scenario == "exhausted" { #expect(!second) }
            let total = scenario == "empty" ? 0 : scenario == "changed-count" && second ? 102 : 101
            let runners = ids.map { id in
                #"{"id":\#(id),"name":"same-name","os":"macOS","status":"offline","busy":false,"labels":[]}"#
            }.joined(separator: ",")
            let headers = scenario == "exhausted" ? ["X-RateLimit-Remaining": "0"] : [:]
            return .init(statusCode: 200, headers: headers, data: Data(
                #"{"total_count":\#(total),"runners":[\#(runners)]}"#.utf8))
        })
        let config = try scenario == "organization" ? configuration("https://github.com/example/") : configuration()
        let result = try await sync.inventory(for: config.gitHubUrl, token: "fixture-token")
        switch result {
        case .available(let runners, let singlePage, let retryAt):
            #expect(["complete", "empty", "organization", "continuation", "last-quota"].contains(scenario))
            #expect(runners.map(\.id) == (["empty", "continuation", "last-quota"].contains(scenario) ? [] : Array(1...101)))
            #expect(singlePage == ["empty", "last-quota"].contains(scenario))
            #expect((retryAt != nil) == (scenario == "last-quota"))
        case .rateLimited:
            #expect(scenario == "exhausted")
        default:
            #expect(!["complete", "empty", "organization", "exhausted", "continuation", "last-quota"].contains(scenario))
        }
    }

    @Test("One exact-scope listing runs after both missing lookups, while multiple pages cannot prove absence",
          arguments: [true, false])
    func reusesScopeListingForMissingRunners(_ singlePage: Bool) async throws {
        let remote = try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: Data(
            #"{"id":21,"name":"local","os":"macOS","status":"online","busy":false,"labels":[]}"#.utf8))
        let requests = RunnerInventoryRequests()
        let scheduler = RunnerSyncScheduler(inventory: { _, _, _ in
            await requests.record("list")
            return .available([remote], singlePage: singlePage)
        }) { _, _, _, _ in
            await requests.record("runner")
            return .notFound
        }
        let existing = try configuration()
        let missing = LocalDotRunnerConfig(agentId: 90, agentName: existing.agentName, gitHubUrl: existing.gitHubUrl)
        let existingRow = UUID()
        let missingRow = UUID()
        let account = RunnerSyncAccount(id: UUID(), credentialKey: "fixture", connectedAt: .distantPast)
        let snapshot = await scheduler.refresh(account: account, runners: [existingRow: existing, missingRow: missing])

        #expect(snapshot?.results[existingRow] == .found(remote, eTag: nil))
        #expect(snapshot?.results[missingRow] == (singlePage ? .missingFromScope : .notFound))
        #expect(await requests.sequence == ["runner", "runner", "list"])
    }

    @Test("A successful scope listing that exhausts quota prevents requests to the next scope")
    func preservesQuotaFromSuccessfulInventory() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let retryAt = now.addingTimeInterval(120)
        let requests = RunnerInventoryRequests()
        let scheduler = RunnerSyncScheduler(inventory: { scope, _, _ in
            await requests.record(scope.path())
            return .available([], singlePage: true, retryAt: retryAt)
        }) { _, _, _, _ in .notFound }
        let firstRow = UUID()
        let secondRow = UUID()
        let configs = try [firstRow: configuration(), secondRow: configuration("https://github.com/example/test")]
        let account = RunnerSyncAccount(id: UUID(), credentialKey: "fixture", connectedAt: .distantPast)

        let snapshot = await scheduler.refresh(account: account, runners: configs, now: now)

        #expect(snapshot?.results[firstRow] == .missingFromScope)
        #expect(snapshot?.results[secondRow] == .rateLimited(retryAt: retryAt))
        #expect(await requests.sequence == ["/example/build"])
    }

    @Test("A conditional response reuses only the selected account’s verified snapshot")
    func validatesCacheScope() async throws {
        let fixture = try configuration()
        let first = RunnerSyncAccount(id: UUID(), credentialKey: "fixture-a", connectedAt: .distantPast)
        let second = RunnerSyncAccount(id: UUID(), credentialKey: "fixture-b", connectedAt: .distantPast)
        let row = UUID()
        let requests = RunnerETagRequests()
        let scheduler = RunnerSyncScheduler { configuration, account, eTag, _ in
            await requests.lookup(configuration, account, eTag)
        }

        let initial = await scheduler.refresh(account: first, runners: [row: fixture])
        let unchanged = await scheduler.refresh(account: first, runners: [row: fixture])
        let other = await scheduler.refresh(account: second, runners: [row: fixture])

        #expect(initial?.results[row] == unchanged?.results[row])
        #expect(initial?.account == first)
        #expect(other?.account == second)
        #expect(await requests.received == [nil, "fixture-etag", nil])
    }

    @Test("Backoff stops remaining lookups and expires against the supplied clock")
    func honorsRateLimitAcrossRunners() async throws {
        let fixture = try configuration()
        let account = RunnerSyncAccount(id: UUID(), credentialKey: "fixture-a", connectedAt: .distantPast)
        let requests = RunnerRateLimitRequests()
        let scheduler = RunnerSyncScheduler { _, _, _, date in await requests.lookup(date) }
        let query = [UUID(): fixture, UUID(): fixture]
        let now = Date(timeIntervalSince1970: 1_000)

        let first = await scheduler.refresh(account: account, runners: query, now: now)
        let early = await scheduler.refresh(account: account, runners: query, now: now.addingTimeInterval(29))
        #expect(await requests.count == 1)
        let after = await scheduler.refresh(account: account, runners: query, now: now.addingTimeInterval(30))

        #expect(first?.results.values.allSatisfy { $0 == .rateLimited(retryAt: now.addingTimeInterval(30)) } == true)
        #expect(early?.results == first?.results)
        #expect(after?.results.values.allSatisfy { $0 == .forbidden } == true)
    }

    @Test("Switching away and back retains the first account’s active backoff")
    func preservesBackoffAfterAccountChange() async throws {
        let first = RunnerSyncAccount(id: UUID(), credentialKey: "fixture-a", connectedAt: .distantPast)
        let second = RunnerSyncAccount(id: UUID(), credentialKey: "fixture-b", connectedAt: .distantPast)
        let requests = RunnerRateLimitRequests()
        let scheduler = RunnerSyncScheduler { _, _, _, date in await requests.lookup(date) }
        let query = [UUID(): try configuration()]
        let now = Date(timeIntervalSince1970: 1_000)
        let limited = await scheduler.refresh(account: first, runners: query, now: now)
        let other = await scheduler.refresh(account: second, runners: query, now: now)
        let reselected = RunnerSyncAccount(id: first.id, credentialKey: first.credentialKey,
                                           connectedAt: first.connectedAt, selectionRevision: UUID())
        let early = await scheduler.refresh(account: reselected, runners: query, now: now.addingTimeInterval(29))

        #expect(other?.results.values.first == .forbidden)
        #expect(early?.results == limited?.results)
        #expect(await requests.count == 2)
    }

    @Test("A delayed response is discarded after switching accounts")
    func discardsObsoleteSnapshot() async throws {
        let first = RunnerSyncAccount(id: UUID(), credentialKey: "fixture-a", connectedAt: .distantPast)
        let second = RunnerSyncAccount(id: UUID(), credentialKey: "fixture-b", connectedAt: .distantPast)
        let gate = RunnerLookupGate()
        let scheduler = RunnerSyncScheduler { _, account, _, _ in
            if account == first { await gate.suspend() }
            return .forbidden
        }
        let query = [UUID(): try configuration()]
        let pending = Task { await scheduler.refresh(account: first, runners: query) }
        await gate.waitForLookup()
        let current = await scheduler.refresh(account: second, runners: query)
        await gate.resume()
        #expect(await pending.value == nil)
        #expect(current?.account == second)
    }

    @MainActor
    @Test("The app discards observations after a selection change, including switching back", arguments: [false, true])
    func rejectsAccountChangedDuringLookup(_ switchBack: Bool) async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let runnerConfig = try configuration()
        let runner = RunnerEntity(name: runnerConfig.agentName, scopeUrl: runnerConfig.gitHubUrl,
                                  workDirectory: URL(fileURLWithPath: "/fixture/_work"))
        runner.githubRunnerId = runnerConfig.agentId
        context.insert(runner)
        let first = GitHubAccountEntity(githubUserId: 21, login: "first", keychainAccountKey: "fixture-a")
        let second = GitHubAccountEntity(githubUserId: 22, login: "second", keychainAccountKey: "fixture-b", isActive: false)
        context.insert(first)
        context.insert(second)
        try context.save()
        let gate = RunnerLookupGate()
        let scheduler = RunnerSyncScheduler { _, account, _, _ in
            if account.credentialKey == "fixture-a" { await gate.suspend() }
            return .forbidden
        }
        let monitor = RunnerRemoteSyncMonitor(scheduler: scheduler)
        let pending = Task { await monitor.refresh(in: context) }
        await gate.waitForLookup()
        try GitHubAccountStore.activate(accountID: second.id, in: context)
        if switchBack { try GitHubAccountStore.activate(accountID: first.id, in: context) }
        await gate.resume()
        await pending.value

        #expect(monitor.snapshot == nil)
        if switchBack { return }
        await monitor.refresh(in: context)
        #expect(monitor.snapshot?.account.id == second.id)
        #expect(monitor.snapshot?.results == [runner.id: .forbidden])
    }

    @MainActor
    @Test("Label changes invalidate an in-flight GitHub scan before the write begins")
    func discardsSnapshotAcrossLabelUpdate() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let config = try configuration()
        let runner = RunnerEntity(name: config.agentName, scopeUrl: config.gitHubUrl,
                                  workDirectory: URL(fileURLWithPath: "/fixture/_work"))
        runner.githubRunnerId = config.agentId
        context.insert(runner)
        context.insert(GitHubAccountEntity(githubUserId: 21, login: "fixture", keychainAccountKey: "fixture"))
        try context.save()
        let gate = RunnerLookupGate()
        let monitor = RunnerRemoteSyncMonitor(scheduler: RunnerSyncScheduler { _, _, _, _ in
            await gate.suspend()
            return .forbidden
        })

        let pending = Task { await monitor.refresh(in: context) }
        await gate.waitForLookup()
        #expect(await monitor.beginLabelUpdate())
        monitor.endLabelUpdate()
        await gate.resume()
        await pending.value

        #expect(monitor.snapshot == nil)
    }

    private func configuration(_ url: String = "https://github.com/example/build") throws -> LocalDotRunnerConfig {
        .init(agentId: 21, agentName: "local", gitHubUrl: try #require(URL(string: url)))
    }
}

private struct RunnerSyncTestTransport: GitHubActionsTransport {
    let respond: @Sendable (URLRequest) throws -> GitHubActionsHTTPResponse

    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        try respond(request)
    }
}

private actor RunnerETagRequests {
    private(set) var received: [String?] = []

    func lookup(_ configuration: LocalDotRunnerConfig, _ account: RunnerSyncAccount, _ eTag: String?) -> RunnerLookupResult {
        received.append(eTag)
        if eTag != nil { return .notModified }
        let data = Data(#"{"id":21,"name":"local","os":"macOS","status":"online","busy":true,"labels":[]}"#.utf8)
        guard let runner = try? JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: data) else {
            Issue.record("Could not decode fixture")
            return .unavailable
        }
        return .found(runner, eTag: "fixture-etag")
    }
}

private actor RunnerRateLimitRequests {
    private(set) var count = 0

    func lookup(_ date: Date) -> RunnerLookupResult {
        count += 1
        return count == 1 ? .rateLimited(retryAt: date.addingTimeInterval(30)) : .forbidden
    }
}

private actor RunnerInventoryRequests {
    private(set) var sequence: [String] = []
    func record(_ request: String) { sequence.append(request) }
}

private actor RunnerLookupGate {
    private var pendingLookup: CheckedContinuation<Void, Never>?
    private var awaitingLookup: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation {
            pendingLookup = $0
            awaitingLookup?.resume()
            awaitingLookup = nil
        }
    }

    func waitForLookup() async {
        guard pendingLookup == nil else { return }
        await withCheckedContinuation { awaitingLookup = $0 }
    }

    func resume() {
        pendingLookup?.resume()
        pendingLookup = nil
    }
}
