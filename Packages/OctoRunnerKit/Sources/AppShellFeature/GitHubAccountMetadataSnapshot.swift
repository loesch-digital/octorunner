import CoreModels
import Foundation

/// Restores only fields touched by an authentication update, preserving unrelated context edits.
@MainActor
struct GitHubAccountMetadataSnapshot {
    let account: GitHubAccountEntity
    let githubUserID: Int64
    let login: String
    let displayName: String?
    let avatar: String?
    let scopes: [String]
    let authMethod: String
    let key: String
    let retiredKeys: [String]
    let connectedAt: Date
    let isActive: Bool

    init(_ account: GitHubAccountEntity) {
        self.account = account
        githubUserID = account.githubUserId
        login = account.login
        displayName = account.displayName
        avatar = account.avatarUrlString
        scopes = account.scopes
        authMethod = account.authMethodRaw
        key = account.keychainAccountKey
        retiredKeys = account.retiredKeychainAccountKeys
        connectedAt = account.connectedAt
        isActive = account.isActive
    }

    func restore() {
        account.githubUserId = githubUserID
        account.login = login
        account.displayName = displayName
        account.avatarUrlString = avatar
        account.scopes = scopes
        account.authMethodRaw = authMethod
        account.keychainAccountKey = key
        account.retiredKeychainAccountKeys = retiredKeys
        account.connectedAt = connectedAt
        account.isActive = isActive
    }
}
