import CoreModels
import Foundation
import Observation
import SecurityKit
import SwiftData

@Observable
@MainActor
public final class AccountSessionController {
    public private(set) var isBusy = false
    public private(set) var error: AccountSessionError?
    private let secrets: any SecretDeleting
    private let save: (ModelContext) throws -> Void

    public init(secrets: any SecretDeleting = KeychainVaultActor()) {
        self.secrets = secrets
        self.save = { try $0.save() }
    }

    init(secrets: any SecretDeleting, save: @escaping (ModelContext) throws -> Void) {
        self.secrets = secrets
        self.save = save
    }

    @discardableResult
    public func disconnect(accountID: UUID, in context: ModelContext) async -> Bool {
        guard !isBusy, !Task.isCancelled else { return false }
        isBusy = true
        error = nil
        defer { isBusy = false }
        do {
            let snapshot = try capture(accountID: accountID, in: context)
            for key in snapshot.keys {
                try Task.checkCancellation()
                guard try matches(snapshot, in: context) else { throw AccountSessionError.accountChanged }
                // Legacy aliases can be shared. Recheck before each deletion.
                guard try !isReferencedElsewhere(key, excluding: accountID, in: context) else { continue }
                do {
                    try await secrets.deleteSecret(account: key, category: "github-oauth")
                } catch {
                    try Task.checkCancellation()
                    throw AccountSessionError.credentialDeletionFailed
                }
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            guard try matches(snapshot, in: context) else { throw AccountSessionError.accountChanged }
            try removeMetadata(snapshot, in: context)
            return true
        } catch is CancellationError {
            return false
        } catch let failure as AccountSessionError {
            guard !Task.isCancelled else { return false }
            error = failure
            return false
        } catch {
            guard !Task.isCancelled else { return false }
            self.error = .metadataPersistenceFailed
            return false
        }
    }

    private struct Snapshot {
        let id: UUID
        let currentKey: String
        let connectedAt: Date
        let keys: [String]
    }

    private func capture(accountID: UUID, in context: ModelContext) throws -> Snapshot {
        let accounts = try context.fetch(FetchDescriptor<GitHubAccountEntity>())
        guard let account = accounts.first(where: { $0.id == accountID }) else { throw AccountSessionError.accountNotFound }
        return Snapshot(id: account.id, currentKey: account.keychainAccountKey, connectedAt: account.connectedAt,
            keys: Array(Set(([account.keychainAccountKey] + account.retiredKeychainAccountKeys).filter { !$0.isEmpty })).sorted())
    }

    private func matches(_ snapshot: Snapshot, in context: ModelContext) throws -> Bool {
        let current = try capture(accountID: snapshot.id, in: context)
        return current.currentKey == snapshot.currentKey && current.connectedAt == snapshot.connectedAt && current.keys == snapshot.keys
    }

    private func isReferencedElsewhere(_ key: String, excluding accountID: UUID, in context: ModelContext) throws -> Bool {
        try context.fetch(FetchDescriptor<GitHubAccountEntity>()).contains {
            $0.id != accountID && ($0.keychainAccountKey == key || $0.retiredKeychainAccountKeys.contains(key))
        }
    }

    private func removeMetadata(_ snapshot: Snapshot, in context: ModelContext) throws {
        guard let account = try context.fetch(FetchDescriptor<GitHubAccountEntity>()).first(where: { $0.id == snapshot.id }) else {
            throw AccountSessionError.accountNotFound
        }
        let login = account.login
        context.delete(account)
        let audit = AuditLogEntity(category: .authentication, severity: .warning,
            title: "GitHub Account Signed Out", summary: "Removed local authentication for @\(login)", actorAccountLogin: login)
        context.insert(audit)
        do {
            try save(context)
        } catch {
            // Undo this deletion only; rolling back the shared context would discard unrelated edits.
            context.insert(account)
            context.delete(audit)
            throw error
        }
    }
}
