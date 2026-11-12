public protocol GitHubAuthenticating: Sendable {
    func requestDeviceCode(scopes: [String]) async throws -> GitHubDeviceCodeResponse
    func pollForAccessToken(deviceCode: String, initialIntervalSeconds: Int) async throws -> AuthenticatedGitHubSession
    func authenticateWithPersonalAccessToken(_ pat: String) async throws -> AuthenticatedGitHubSession
    func discardSessionCredential(_ session: AuthenticatedGitHubSession) async throws
}
