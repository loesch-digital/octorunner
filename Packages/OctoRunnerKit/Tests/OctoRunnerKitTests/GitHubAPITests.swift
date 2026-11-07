import Foundation
import GitHubAPI
import SecurityKit
import Testing

@Suite("GitHubAPI, RFC 8628 Device Flow & AppUpdater Tests")
struct GitHubAPITests {
    @Test("GitHubRunnerDownloadDTO decodes snake_case GitHub REST API JSON")
    func runnerDownloadDTODecoding() throws {
        let json = """
        {
          "os": "osx",
          "architecture": "arm64",
          "download_url": "https://github.com/actions/runner/releases/download/v2.338.2/actions-runner-osx-arm64-2.338.2.tar.gz",
          "filename": "actions-runner-osx-arm64-2.338.2.tar.gz",
          "sha256_checksum": "a1b2c3d4e5f6"
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(GitHubRunnerDownloadDTO.self, from: json)
        #expect(dto.os == "osx")
        #expect(dto.architecture == "arm64")
        #expect(dto.filename == "actions-runner-osx-arm64-2.338.2.tar.gz")
        #expect(dto.sha256Checksum == "a1b2c3d4e5f6")
    }

    @Test("GitHubDeviceCodeResponse and GitHubOAuthTokenResponse RFC 8628 JSON decoding")
    func oauthDeviceCodeAndTokenDecoding() throws {
        let deviceCodeJSON = """
        {
          "device_code": "3584d83530557fdd1f46af8289938c8ef79f9dc5",
          "user_code": "WDX8-8222",
          "verification_uri": "https://github.com/login/device",
          "expires_in": 900,
          "interval": 5
        }
        """.data(using: .utf8)!

        let decodedCode = try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: deviceCodeJSON)
        #expect(decodedCode.userCode == "WDX8-8222")
        #expect(decodedCode.expiresIn == 900)
        #expect(decodedCode.interval == 5)

        let pendingJSON = """
        {
          "error": "authorization_pending",
          "error_description": "The authorization request is still pending."
        }
        """.data(using: .utf8)!
        let decodedPending = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: pendingJSON)
        #expect(decodedPending.error == "authorization_pending")
        #expect(decodedPending.accessToken == nil)

        let tokenJSON = """
        {
          "access_token": "gho_16C7e42F292c6912E7710c838347Ae178B4a",
          "token_type": "bearer",
          "scope": "admin:org,repo,workflow"
        }
        """.data(using: .utf8)!
        let decodedToken = try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: tokenJSON)
        #expect(decodedToken.accessToken == "gho_16C7e42F292c6912E7710c838347Ae178B4a")
        #expect(decodedToken.error == nil)
    }

    @Test("GitHubOAuthActor X-OAuth-Scopes header parsing, default Client ID, and empty PAT rejection")
    func oauthScopesParsingAndValidation() async throws {
        #expect(GitHubOAuthConfig.defaultClientID == "Ov23liD1qcIUTp8adWQd")
        let scopes = GitHubOAuthActor.parseScopes(from: "repo, workflow, admin:org")
        #expect(scopes == ["repo", "workflow", "admin:org"])
        #expect(GitHubOAuthActor.parseScopes(from: "").isEmpty)

        let actor = GitHubOAuthActor(
            keychain: KeychainVaultActor(servicePrefix: "io.octorunner.macos.tests.\(UUID().uuidString)")
        )
        await #expect(throws: GitHubAuthError.invalidTokenOrUnauthorized) {
            try await actor.authenticateWithPersonalAccessToken("   ")
        }
    }

    @Test("AppUpdaterActor semantic version comparison and GitHubReleaseDTO decoding")
    func appUpdaterVersionComparisonAndDecoding() throws {
        #expect(AppUpdaterActor.isVersion("v0.2.3", newerThan: "0.2.2") == true)
        #expect(AppUpdaterActor.isVersion("0.3.0", newerThan: "0.2.9") == true)
        #expect(AppUpdaterActor.isVersion("1.0.0", newerThan: "0.9.9") == true)
        #expect(AppUpdaterActor.isVersion("0.2.3", newerThan: "0.2.3") == false)
        #expect(AppUpdaterActor.isVersion("0.1.9", newerThan: "0.2.0") == false)

        let releaseJSON = """
        {
          "tag_name": "v0.2.3",
          "name": "OctoRunner v0.2.3",
          "body": "Auto-updater and account profile menu.",
          "html_url": "https://github.com/loesch-digital/octorunner/releases/tag/v0.2.3",
          "published_at": "2026-11-07T16:00:00Z",
          "assets": [
            {
              "name": "OctoRunner-0.2.3-arm64.zip",
              "browser_download_url": "https://github.com/loesch-digital/octorunner/releases/download/v0.2.3/OctoRunner-0.2.3-arm64.zip",
              "size": 1245184
            }
          ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(GitHubReleaseDTO.self, from: releaseJSON)
        #expect(decoded.tagName == "v0.2.3")
        #expect(decoded.assets.first?.name == "OctoRunner-0.2.3-arm64.zip")
    }
}
