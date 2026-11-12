import CoreModels
import Foundation
import SecurityKit

public actor GitHubOAuthActor: GitHubAuthenticating {
    private let transport: any GitHubActionsTransport
    private let keychain: KeychainVaultActor
    private let tokenWriter: any SecretWriting
    private let clientID: String

    public init(
        session: URLSession = .shared,
        keychain: KeychainVaultActor = KeychainVaultActor(),
        clientID: String = GitHubOAuthConfig.defaultClientID,
        transport: (any GitHubActionsTransport)? = nil,
        tokenWriter: (any SecretWriting)? = nil
    ) {
        self.transport = transport ?? GitHubActionsURLSessionTransport(session: session)
        self.keychain = keychain
        self.tokenWriter = tokenWriter ?? keychain
        self.clientID = clientID
    }

    /// Step 1 of RFC 8628 Device Flow: Request temporary `device_code` and `user_code`.
    public func requestDeviceCode(scopes: [String] = GitHubOAuthConfig.defaultScopes) async throws -> GitHubDeviceCodeResponse {
        try Task.checkCancellation()
        var request = URLRequest(url: GitHubOAuthConfig.deviceCodeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let scopeParam = scopes.joined(separator: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "repo"
        let bodyString = "client_id=\(clientID)&scope=\(scopeParam)"
        request.httpBody = bodyString.data(using: .utf8)

        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAuthError.invalidHTTPStatus(response.statusCode)
        }
        return try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: response.data)
    }

    /// Step 2 of RFC 8628 Device Flow: Poll GitHub until the user authorizes in browser or cancels.
    public func pollForAccessToken(
        deviceCode: String,
        initialIntervalSeconds: Int
    ) async throws -> AuthenticatedGitHubSession {
        var currentInterval = max(initialIntervalSeconds, 5)

        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(currentInterval))
            try Task.checkCancellation()

            let tokenResponse = try await requestAccessTokenOnce(deviceCode: deviceCode)

            if let token = tokenResponse.accessToken, !token.isEmpty {
                return try await validateAndStoreToken(token, authMethod: "oauth_device")
            }

            switch tokenResponse.error {
            case "authorization_pending":
                continue
            case "slow_down":
                currentInterval = (tokenResponse.interval ?? currentInterval) + 5
                continue
            case "expired_token":
                throw GitHubAuthError.expiredDeviceCode
            case "access_denied":
                throw GitHubAuthError.accessDenied
            case .some(let errCode):
                throw GitHubAuthError.unexpectedResponse(tokenResponse.errorDescription ?? errCode)
            case .none:
                throw GitHubAuthError.unexpectedResponse("Neither access_token nor error returned")
            }
        }
    }

    /// Personal Access Token (PAT) validation & Keychain storage.
    public func authenticateWithPersonalAccessToken(_ pat: String) async throws -> AuthenticatedGitHubSession {
        try Task.checkCancellation()
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubAuthError.invalidTokenOrUnauthorized
        }
        return try await validateAndStoreToken(trimmed, authMethod: "pat")
    }

    /// Validate token against `GET https://api.github.com/user`, verify scopes, and store in macOS Keychain.
    public func validateAndStoreToken(_ token: String, authMethod: String) async throws -> AuthenticatedGitHubSession {
        try Task.checkCancellation()
        var request = URLRequest(url: GitHubOAuthConfig.userProfileEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let response = try await transport.send(request)
        try Task.checkCancellation()
        if response.statusCode == 401 || response.statusCode == 403 {
            throw GitHubAuthError.invalidTokenOrUnauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAuthError.invalidHTTPStatus(response.statusCode)
        }

        let userProfile = try JSONDecoder().decode(GitHubUserProfileDTO.self, from: response.data)
        let scopesHeader = response.headers["x-oauth-scopes"] ?? ""
        let parsedScopes = Self.parseScopes(from: scopesHeader)

        // Save token in macOS Keychain (never in SwiftData or UserDefaults)
        guard userProfile.id > 0 else { throw GitHubAuthError.invalidTokenOrUnauthorized }
        let authenticated = AuthenticatedGitHubSession(user: userProfile, scopes: parsedScopes, authMethod: authMethod)
        try await tokenWriter.saveSecret(token, account: authenticated.keychainAccountKey, category: "github-oauth")
        do {
            try Task.checkCancellation()
        } catch {
            // Remove only this staged version. Cleanup intentionally survives cancellation.
            try await keychain.deleteSecret(account: authenticated.keychainAccountKey, category: "github-oauth")
            throw error
        }

        return authenticated
    }

    public func discardSessionCredential(_ session: AuthenticatedGitHubSession) async throws {
        try await keychain.deleteSecret(account: session.keychainAccountKey, category: "github-oauth")
    }

    public static func parseScopes(from headerValue: String) -> [String] {
        headerValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func requestAccessTokenOnce(deviceCode: String) async throws -> GitHubOAuthTokenResponse {
        try Task.checkCancellation()
        var request = URLRequest(url: GitHubOAuthConfig.accessTokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = bodyString.data(using: .utf8)

        let response = try await transport.send(request)
        try Task.checkCancellation()
        guard (200..<300).contains(response.statusCode) else {
            throw GitHubAuthError.invalidHTTPStatus(response.statusCode)
        }
        return try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: response.data)
    }
}
