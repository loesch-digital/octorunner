import Foundation
import SwiftData

@Model
public final class GitHubAccountEntity {
    #Index<GitHubAccountEntity>([\.login])

    public var id: UUID
    public var githubUserId: Int64
    public var login: String
    public var displayName: String?
    public var avatarUrlString: String?
    public var scopes: [String]
    public var authMethodRaw: String
    public var keychainAccountKey: String
    public var connectedAt: Date
    public var isActive: Bool

    public init(
        id: UUID = UUID(),
        githubUserId: Int64,
        login: String,
        displayName: String? = nil,
        avatarUrlString: String? = nil,
        scopes: [String] = ["repo", "workflow", "admin:org"],
        authMethodRaw: String = "oauth_device",
        keychainAccountKey: String,
        connectedAt: Date = .now,
        isActive: Bool = true
    ) {
        self.id = id
        self.githubUserId = githubUserId
        self.login = login
        self.displayName = displayName
        self.avatarUrlString = avatarUrlString
        self.scopes = scopes
        self.authMethodRaw = authMethodRaw
        self.keychainAccountKey = keychainAccountKey
        self.connectedAt = connectedAt
        self.isActive = isActive
    }
}
