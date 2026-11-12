import Foundation
import GitHubAPI
import SecurityKit
import Testing

struct OAuthValidationTests {
    @Test("Malformed token values are rejected before constructing an HTTP credential header", arguments: ["bad\nvalue", "bad\u{0000}value", "tøkén"])
    func malformedTokens(_ token: String) async {
        let transport = OAuthValidationTransport()
        let writer = OAuthValidationWriter()
        let actor = GitHubOAuthActor(transport: transport, tokenWriter: writer)
        await #expect(throws: GitHubAuthError.invalidTokenOrUnauthorized) {
            try await actor.authenticateWithPersonalAccessToken(token)
        }
        #expect(await transport.calls == 0)
        #expect(await writer.saves == 0)
    }

    @Test("Profile authentication uses the current verified REST version and saves only an identity-bound credential")
    func versionedProfile() async throws {
        let transport = OAuthValidationTransport()
        let writer = OAuthValidationWriter()
        let actor = GitHubOAuthActor(transport: transport, tokenWriter: writer)
        let session = try await actor.authenticateWithPersonalAccessToken("synthetic-fixture")
        #expect(await transport.apiVersion == "2026-03-10")
        #expect(session.user.id == 7 && session.scopes == ["read:org"])
        #expect(await writer.account == session.keychainAccountKey)
        #expect(session.keychainAccountKey.hasPrefix("github-user:7:"))
    }

    @Test("HTTP authentication errors never store a credential", arguments: [401, 403, 429, 500])
    func rejectsHTTPFailure(_ status: Int) async {
        let writer = OAuthValidationWriter()
        let actor = GitHubOAuthActor(transport: OAuthValidationTransport(status: status), tokenWriter: writer)
        let expected: GitHubAuthError = [401, 403].contains(status) ? .invalidTokenOrUnauthorized : .invalidHTTPStatus(status)
        await #expect(throws: expected) { try await actor.authenticateWithPersonalAccessToken("synthetic-fixture") }
        #expect(await writer.saves == 0)
    }

    @Test("A profile without a valid GitHub identity never gains a credential")
    func invalidIdentity() async {
        let writer = OAuthValidationWriter()
        let actor = GitHubOAuthActor(transport: OAuthValidationTransport(userID: 0), tokenWriter: writer)
        await #expect(throws: GitHubAuthError.invalidTokenOrUnauthorized) {
            try await actor.authenticateWithPersonalAccessToken("synthetic-fixture")
        }
        #expect(await writer.saves == 0)
    }

    @Test("Cancellation after the profile request prevents credential storage")
    func cancelledProfileResponse() async {
        let writer = OAuthValidationWriter()
        let actor = GitHubOAuthActor(transport: OAuthValidationTransport(cancelResponse: true), tokenWriter: writer)
        let task = Task<Void, Never> {
            await #expect(throws: CancellationError.self) {
                try await actor.authenticateWithPersonalAccessToken("synthetic-fixture")
            }
        }
        await task.value
        #expect(await writer.saves == 0)
    }
}

private actor OAuthValidationWriter: SecretWriting {
    private(set) var saves = 0
    private(set) var account: String?
    func saveSecret(_ secret: String, account: String, category: String) async throws {
        saves += 1
        self.account = account
    }
}

private actor OAuthValidationTransport: GitHubActionsTransport {
    let status: Int
    let userID: Int64
    let cancelResponse: Bool
    private(set) var calls = 0
    private(set) var apiVersion: String?
    init(status: Int = 200, userID: Int64 = 7, cancelResponse: Bool = false) {
        self.status = status; self.userID = userID; self.cancelResponse = cancelResponse
    }
    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        calls += 1
        apiVersion = request.value(forHTTPHeaderField: "X-GitHub-Api-Version")
        if cancelResponse { withUnsafeCurrentTask { $0?.cancel() } }
        return GitHubActionsHTTPResponse(statusCode: status, headers: ["X-OAuth-Scopes": "read:org"],
            data: Data("{\"id\":\(userID),\"login\":\"fixture\"}".utf8))
    }
}
