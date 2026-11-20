import Foundation
import GitHubAPI
@testable import RunnerEngine
import SyncKit
import Testing

struct RunnerMigrationGitHubChecksTests {
    @Test("Repository identity is read from the exact GitHub scope and a forbidden response is treated as unavailable")
    func inaccessibleRunner() async throws {
        let config = try Self.configuration("https://github.com/example/runner-repo")
        let transport = MigrationGitHubTransport { request in
            #expect(request.url?.absoluteString == "https://api.github.com/repos/example/runner-repo/actions/runners/21")
            #expect(request.httpMethod == "GET")
            #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
            return .init(statusCode: 403, headers: [:], data: Data())
        }
        let checks = RunnerMigrationGitHubChecks(transport: transport)

        #expect(try await checks.runner(for: config, token: "synthetic") == nil)
    }

    @Test("A replaced ID requires affirmative absence of the old registration", arguments: [200, 403, 404])
    func verifiesPreviousRegistrationBeforeAdoptingAnotherID(_ status: Int) async throws {
        let config = try Self.configuration("https://github.com/example/runner-repo")
        let transport = MigrationGitHubTransport { request in
            #expect(request.url?.absoluteString == "https://api.github.com/repos/example/runner-repo/actions/runners/21")
            return .init(statusCode: status, headers: [:], data: Data())
        }
        let checks = RunnerMigrationGitHubChecks(transport: transport)
        let absent = try await checks.previousRunnerIsAbsent(for: config, token: "synthetic")
        #expect(absent == (status == 404))
    }

    @Test("An organization group is confirmed only when it lists the exact runner")
    func groupMembership() async throws {
        let config = try Self.configuration("https://github.com/example")
        let transport = MigrationGitHubTransport { request in
            let url = try #require(request.url)
            switch url.absoluteString {
            case "https://api.github.com/orgs/example/actions/runner-groups/3":
                return Self.response(#"{"id":3,"name":"Build"}"#)
            case "https://api.github.com/orgs/example/actions/runner-groups/3/runners?per_page=100&page=1":
                let ids = (100...199).map { #"{"id":\#($0)}"# }.joined(separator: ",")
                return Self.response(#"{"total_count":101,"runners":[\#(ids)]}"#)
            case "https://api.github.com/orgs/example/actions/runner-groups/3/runners?per_page=100&page=2":
                return Self.response(#"{"total_count":101,"runners":[{"id":21}]}"#)
            default:
                Issue.record("Unexpected GitHub request")
                return .init(statusCode: 404, headers: [:], data: Data())
            }
        }
        let checks = RunnerMigrationGitHubChecks(transport: transport)

        #expect(try await checks.group(for: config, runnerID: 21, token: "synthetic") == .init(id: 3, name: "Build"))
        #expect(try await checks.group(for: config, runnerID: 22, token: "synthetic") == nil)
    }

    private static func configuration(_ scope: String) throws -> LocalDotRunnerConfig {
        LocalDotRunnerConfig(agentId: 21, agentName: "macbook-pro", poolId: 3, poolName: "Build",
                             gitHubUrl: try #require(URL(string: scope)))
    }

    private static func response(_ json: String) -> GitHubActionsHTTPResponse {
        .init(statusCode: 200, headers: [:], data: Data(json.utf8))
    }
}

private struct MigrationGitHubTransport: GitHubActionsTransport {
    let respond: @Sendable (URLRequest) throws -> GitHubActionsHTTPResponse

    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        try respond(request)
    }
}
