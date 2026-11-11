import CoreModels
import Foundation
import SecurityKit

public actor GitHubOAuthActor {
    private let session: URLSession
    private let keychain: KeychainVaultActor
    private let clientID: String

    public init(
        session: URLSession = .shared,
        keychain: KeychainVaultActor = KeychainVaultActor(),
        clientID: String = GitHubOAuthConfig.defaultClientID
    ) {
        self.session = session
        self.keychain = keychain
        self.clientID = clientID
    }

    /// Step 1 of RFC 8628 Device Flow: Request temporary `device_code` and `user_code`.
    public func requestDeviceCode(scopes: [String] = GitHubOAuthConfig.defaultScopes) async throws -> GitHubDeviceCodeResponse {
        var request = URLRequest(url: GitHubOAuthConfig.deviceCodeEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let scopeParam = scopes.joined(separator: " ").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "repo"
        let bodyString = "client_id=\(clientID)&scope=\(scopeParam)"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAuthError.unexpectedResponse("Missing HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubAuthError.invalidHTTPStatus(http.statusCode)
        }
        return try JSONDecoder().decode(GitHubDeviceCodeResponse.self, from: data)
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
        let trimmed = pat.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw GitHubAuthError.invalidTokenOrUnauthorized
        }
        return try await validateAndStoreToken(trimmed, authMethod: "pat")
    }

    /// Validate token against `GET https://api.github.com/user`, verify scopes, and store in macOS Keychain.
    public func validateAndStoreToken(_ token: String, authMethod: String) async throws -> AuthenticatedGitHubSession {
        var request = URLRequest(url: GitHubOAuthConfig.userProfileEndpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAuthError.unexpectedResponse("Invalid HTTP response")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw GitHubAuthError.invalidTokenOrUnauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            throw GitHubAuthError.invalidHTTPStatus(http.statusCode)
        }

        let userProfile = try JSONDecoder().decode(GitHubUserProfileDTO.self, from: data)
        let scopesHeader = http.value(forHTTPHeaderField: "X-OAuth-Scopes") ?? ""
        let parsedScopes = Self.parseScopes(from: scopesHeader)

        // Save token in macOS Keychain (never in SwiftData or UserDefaults)
        try await keychain.saveSecret(token, account: userProfile.login, category: "github-oauth")

        return AuthenticatedGitHubSession(
            user: userProfile,
            scopes: parsedScopes,
            authMethod: authMethod
        )
    }

    public func signOut(login: String) async throws {
        try await keychain.deleteSecret(account: login, category: "github-oauth")
    }

    public static func parseScopes(from headerValue: String) -> [String] {
        headerValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func requestAccessTokenOnce(deviceCode: String) async throws -> GitHubOAuthTokenResponse {
        var request = URLRequest(url: GitHubOAuthConfig.accessTokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyString = "client_id=\(clientID)&device_code=\(deviceCode)&grant_type=urn:ietf:params:oauth:grant-type:device_code"
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw GitHubAuthError.invalidHTTPStatus(status)
        }
        return try JSONDecoder().decode(GitHubOAuthTokenResponse.self, from: data)
    }
}
