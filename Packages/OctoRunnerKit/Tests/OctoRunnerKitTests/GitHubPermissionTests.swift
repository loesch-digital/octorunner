import Foundation
import GitHubAPI
import SecurityKit
import Testing

// Immutable fixtures: each request carries its own scenario, with no shared handler state.
final class PermissionFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        var status = 200
        var headers: [String: String] = ["Content-Type": "application/json"]
        let body: String
        if url.path == "/login/device/code" {
            var data = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    data.append(contentsOf: buffer.prefix(count))
                }
            }
            let requestBody = String(decoding: data, as: UTF8.self)
            let decoded = requestBody.removingPercentEncoding ?? requestBody
            if decoded.contains("workflow") { status = 400 }
            body = """
            {"device_code":"test-device","user_code":"TEST-CODE","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}
            """
        } else {
            if let scopes = request.value(forHTTPHeaderField: "X-Fixture-Scopes") { headers["X-OAuth-Scopes"] = scopes }
            body = """
            {"id":42,"login":"permission-fixture","name":"Fixture","avatar_url":null}
            """
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func session(scopes: String? = nil) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PermissionFixtureProtocol.self]
        if let scopes { configuration.httpAdditionalHeaders = ["X-Fixture-Scopes": scopes] }
        return URLSession(configuration: configuration)
    }
}

@Suite("GitHub least privilege and truthful token permissions")
struct GitHubPermissionTests {
    @Test("Device flow does not request permission to modify workflow files")
    func deviceFlowDoesNotRequestWorkflowWrites() async throws {
        let session = PermissionFixtureProtocol.session()
        defer { session.invalidateAndCancel() }
        let actor = GitHubOAuthActor(session: session)
        let result = try await actor.requestDeviceCode()
        #expect(result.userCode == "TEST-CODE")
    }

    @Test("PATs without OAuth scope headers never claim unverified default privileges")
    func fineGrainedTokenDoesNotInventScopes() async throws {
        let session = PermissionFixtureProtocol.session()
        defer { session.invalidateAndCancel() }
        let vault = KeychainVaultActor(servicePrefix: "io.octorunner.permission-test.\(UUID().uuidString)")
        let actor = GitHubOAuthActor(session: session, keychain: vault)
        let result = try await actor.authenticateWithPersonalAccessToken("fixture-token")
        let stored = try await vault.readSecret(account: result.keychainAccountKey)
        #expect(try await vault.readSecret(account: "permission-fixture") == nil)
        try await vault.deleteSecret(account: result.keychainAccountKey)
        #expect(result.scopes.isEmpty)
        #expect(stored == "fixture-token")
    }

    @Test("Only actually granted classic OAuth scopes are reported")
    func grantedScopesRemainAccurate() async throws {
        let session = PermissionFixtureProtocol.session(scopes: "repo, read:org")
        defer { session.invalidateAndCancel() }
        let vault = KeychainVaultActor(servicePrefix: "io.octorunner.permission-test.\(UUID().uuidString)")
        let actor = GitHubOAuthActor(session: session, keychain: vault)
        let result = try await actor.authenticateWithPersonalAccessToken("fixture-token")
        try await vault.deleteSecret(account: result.keychainAccountKey)
        #expect(result.scopes == ["repo", "read:org"])
    }
}
