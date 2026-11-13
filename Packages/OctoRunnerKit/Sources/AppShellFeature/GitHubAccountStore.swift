import CoreModels
import Foundation
import GitHubAPI
import SwiftData

@MainActor
public enum GitHubAccountStore {
    /// Saves metadata only. The authenticator has already stored the credential.
    @discardableResult
    public static func upsert(_ session: AuthenticatedGitHubSession, in context: ModelContext) throws -> GitHubAccountEntity {
        try upsert(session, in: context, save: { try context.save() })
    }

    @discardableResult
    static func upsert(_ session: AuthenticatedGitHubSession, in context: ModelContext, save: () throws -> Void) throws -> GitHubAccountEntity {
        try Task.checkCancellation()
        let login = session.user.login
        let credentialKey = session.keychainAccountKey
        guard session.user.id > 0, !login.isEmpty, login.utf8.allSatisfy({
            (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 45
        }) else { throw GitHubAccountStoreError.invalidIdentity }
        let accounts = try context.fetch(FetchDescriptor<GitHubAccountEntity>())
        let snapshots = accounts.map(GitHubAccountMetadataSnapshot.init)
        let existing = accounts.first { $0.githubUserId == session.user.id }
            ?? accounts.first { $0.githubUserId == 0 && $0.login.caseInsensitiveCompare(login) == .orderedSame }
        let account = existing ?? GitHubAccountEntity(githubUserId: session.user.id, login: login, scopes: [], keychainAccountKey: credentialKey)
        let previousLogin = existing?.login
        if !account.keychainAccountKey.isEmpty, account.keychainAccountKey != credentialKey {
            account.retiredKeychainAccountKeys = Array(Set(account.retiredKeychainAccountKeys + [account.keychainAccountKey])).sorted()
        }
        account.retiredKeychainAccountKeys.removeAll { $0 == credentialKey }
        for other in accounts where other.id != account.id {
            other.isActive = false
            // Legacy login aliases cannot establish identity after a name was reclaimed.
            if other.githubUserId != session.user.id, other.keychainAccountKey.caseInsensitiveCompare(login) == .orderedSame {
                other.retiredKeychainAccountKeys = Array(Set(other.retiredKeychainAccountKeys + [other.keychainAccountKey])).sorted()
                other.keychainAccountKey = ""
            }
        }
        account.githubUserId = session.user.id
        account.login = login
        account.displayName = session.user.name
        account.avatarUrlString = session.user.avatarUrl
        account.scopes = session.scopes
        account.authMethodRaw = session.authMethod
        account.keychainAccountKey = credentialKey
        account.connectedAt = .now
        account.isActive = true
        if existing == nil { context.insert(account) }
        let audit = AuditLogEntity(category: .authentication, title: "GitHub Account Connected",
            summary: "Authenticated @\(login) via \(session.authMethod)", actorAccountLogin: login,
            previousValue: previousLogin, newValue: session.scopes.joined(separator: ","))
        context.insert(audit)
        do {
            try save()
        } catch {
            snapshots.forEach { $0.restore() }
            if existing == nil { context.delete(account) }
            context.delete(audit)
            throw error
        }
        return account
    }

    public static func activate(accountID: UUID, in context: ModelContext) throws {
        try activate(accountID: accountID, in: context, save: { try context.save() })
    }

    static func activate(accountID: UUID, in context: ModelContext, save: () throws -> Void) throws {
        try Task.checkCancellation()
        let accounts = try context.fetch(FetchDescriptor<GitHubAccountEntity>())
        let snapshots = accounts.map(GitHubAccountMetadataSnapshot.init)
        guard let selected = accounts.first(where: { $0.id == accountID }) else { throw GitHubAccountStoreError.accountNotFound }
        guard !selected.keychainAccountKey.isEmpty else { throw GitHubAccountStoreError.reauthenticationRequired }
        for account in accounts { account.isActive = account.id == selected.id }
        let audit = AuditLogEntity(category: .authentication, title: "GitHub Account Switched",
            summary: "Selected @\(selected.login)", actorAccountLogin: selected.login)
        context.insert(audit)
        do {
            try save()
        } catch {
            snapshots.forEach { $0.restore() }
            context.delete(audit)
            throw error
        }
    }
}
