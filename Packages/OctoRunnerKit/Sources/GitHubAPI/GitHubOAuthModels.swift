import Foundation

public enum GitHubOAuthConfig {
    /// Public OAuth Client ID for OctoRunner (RFC 8628 Device Flow — not a secret).
    public static let defaultClientID = "Ov23liD1qcIUTp8adWQd"
    public static let defaultScopes = ["repo", "workflow", "admin:org"]
    public static let deviceCodeEndpoint = URL(string: "https://github.com/login/device/code")!
    public static let accessTokenEndpoint = URL(string: "https://github.com/login/oauth/access_token")!
    public static let userProfileEndpoint = URL(string: "https://api.github.com/user")!
}

public struct GitHubDeviceCodeResponse: Codable, Sendable, Equatable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: URL
    public let expiresIn: Int
    public let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationUri = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    public init(
        deviceCode: String,
        userCode: String,
        verificationUri: URL,
        expiresIn: Int,
        interval: Int
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationUri = verificationUri
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

public struct GitHubOAuthTokenResponse: Codable, Sendable, Equatable {
    public let accessToken: String?
    public let tokenType: String?
    public let scope: String?
    public let error: String?
    public let errorDescription: String?
    public let interval: Int?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
        case interval
    }
}

public struct GitHubUserProfileDTO: Codable, Sendable, Equatable {
    public let id: Int64
    public let login: String
    public let name: String?
    public let avatarUrl: String?

    enum CodingKeys: String, CodingKey {
        case id
        case login
        case name
        case avatarUrl = "avatar_url"
    }

    public init(id: Int64, login: String, name: String? = nil, avatarUrl: String? = nil) {
        self.id = id
        self.login = login
        self.name = name
        self.avatarUrl = avatarUrl
    }
}

public struct AuthenticatedGitHubSession: Sendable, Equatable {
    public let user: GitHubUserProfileDTO
    public let scopes: [String]
    public let authMethod: String

    public init(user: GitHubUserProfileDTO, scopes: [String], authMethod: String) {
        self.user = user
        self.scopes = scopes
        self.authMethod = authMethod
    }
}

public enum GitHubAuthError: LocalizedError, Sendable, Equatable {
    case invalidHTTPStatus(Int)
    case expiredDeviceCode
    case accessDenied
    case invalidTokenOrUnauthorized
    case missingRequiredScopes([String])
    case unexpectedResponse(String)

    public var errorDescription: String? {
        switch self {
        case .invalidHTTPStatus(let code):
            return "GitHub returned HTTP status \(code)."
        case .expiredDeviceCode:
            return "The device authorization code has expired. Please request a new code."
        case .accessDenied:
            return "Authorization was cancelled or denied in the browser."
        case .invalidTokenOrUnauthorized:
            return "The provided GitHub token is invalid or expired."
        case .missingRequiredScopes(let missing):
            return "Missing required token scopes: \(missing.joined(separator: ", "))."
        case .unexpectedResponse(let detail):
            return "Unexpected response from GitHub: \(detail)"
        }
    }
}
