import Foundation
import GitHubAPI
import Testing

struct RunnerProvisioningAPITests {
    @Test("Registration uses the exact scope and only returns its decoded short-lived token",
          arguments: ["repos/example/build", "orgs/example"])
    func registrationToken(_ scope: String) async throws {
        let inputPath = scope.split(separator: "/", maxSplits: 1)[1]
        let url = try #require(URL(string: "https://github.com/\(inputPath)"))
        let client = GitHubRunnerProvisioningClient(transport: ProvisioningTestTransport { request in
            #expect(request.url?.absoluteString == "https://api.github.com/\(scope)/actions/runners/registration-token")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fixture-account-token")
            #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
            #expect(!request.httpShouldHandleCookies)
            let data = Data(#"{"token":"fixture-registration-token","expires_at":"2026-11-20T12:00:00Z"}"#.utf8)
            return .init(statusCode: 201, headers: [:], data: data)
        })
        let registration = try await client.createRegistrationToken(scopeURL: url, token: "fixture-account-token")
        #expect(registration.token == "fixture-registration-token")
        #expect(registration.expiresAt == "2026-11-20T12:00:00Z")
    }

    @Test("Provisioning does not include an upstream response body in errors")
    func omitsErrorBody() async throws {
        let client = GitHubRunnerProvisioningClient(transport: ProvisioningTestTransport { _ in
            .init(statusCode: 403, headers: [:], data: Data("fixture-secret-in-body".utf8))
        })
        let scope = try #require(URL(string: "https://github.com/example/build"))
        do {
            _ = try await client.createRegistrationToken(scopeURL: scope, token: "fixture-account-token")
            Issue.record("Expected a permission failure")
        } catch GitHubProvisioningError.httpError(let status, let detail) {
            #expect(status == 403)
            #expect(!detail.contains("fixture-secret"))
        }
    }

    @Test("Applying custom labels returns GitHub’s verified label list")
    func returnsReportedLabels() async throws {
        let client = GitHubRunnerProvisioningClient(transport: ProvisioningTestTransport { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.absoluteString == "https://api.github.com/repos/example/build/actions/runners/22/labels")
            let data = Data(#"{"total_count":2,"labels":[{"name":"self-hosted","type":"read-only"},{"name":"xcode","type":"custom"}]}"#.utf8)
            return .init(statusCode: 200, headers: [:], data: data)
        })
        let scope = try #require(URL(string: "https://github.com/example/build"))
        #expect(try await client.replaceRunnerLabels(scopeURL: scope, runnerId: 22, labels: ["xcode"], token: "fixture-token")
                == ["self-hosted", "xcode"])
    }

    @Test("Invalid provisioning scopes fail before sending credentials")
    func rejectsInvalidScope() async throws {
        let client = GitHubRunnerProvisioningClient(transport: ProvisioningTestTransport { _ in
            Issue.record("Invalid scope reached the transport")
            return .init(statusCode: 403, headers: [:], data: Data())
        })
        let scope = try #require(URL(string: "https://example.com/example/build"))
        await #expect(throws: GitHubProvisioningError.self) {
            _ = try await client.createRegistrationToken(scopeURL: scope, token: "fixture-account-token")
        }
    }
}

private struct ProvisioningTestTransport: GitHubActionsTransport {
    let respond: @Sendable (URLRequest) -> GitHubActionsHTTPResponse

    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        respond(request)
    }
}
