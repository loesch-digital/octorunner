import CoreModels
import Foundation
import GitHubAPI
import SwiftData
import Testing
@testable import AppShellFeature

@MainActor
struct GitHubAccountStoreTests {
    private static var containers: [ModelContainer] = []

    private enum SaveFailure: Error { case fixture }

    @Test("A failed account save restores only authentication changes and preserves unrelated edits", arguments: [false, true])
    func failedSave(existing: Bool) throws {
        let context = try makeContext()
        let old = GitHubAccountEntity(githubUserId: 7, login: "before", keychainAccountKey: "legacy")
        context.insert(old)
        try context.save()
        old.displayName = "Unrelated pending edit"
        let authentication = session(id: existing ? 7 : 8, login: "after")
        #expect(throws: SaveFailure.self) {
            try GitHubAccountStore.upsert(authentication, in: context, save: { throw SaveFailure.fixture })
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 1)
        #expect(old.login == "before" && old.keychainAccountKey == "legacy" && old.isActive)
        #expect(old.displayName == "Unrelated pending edit")
        #expect(old.retiredKeychainAccountKeys.isEmpty)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
    }

    @Test("Failed account activation restores the prior active account without a success audit")
    func failedActivation() throws {
        let context = try makeContext()
        let first = try GitHubAccountStore.upsert(session(id: 7, login: "first"), in: context)
        let second = try GitHubAccountStore.upsert(session(id: 8, login: "second"), in: context)
        #expect(throws: SaveFailure.self) {
            try GitHubAccountStore.activate(accountID: first.id, in: context, save: { throw SaveFailure.fixture })
        }
        try context.save()
        #expect(second.isActive && !first.isActive)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 2)
    }

    @Test("Unknown token scopes remain unknown instead of inventing broad OAuth permissions")
    func noInventedScopes() {
        let account = GitHubAccountEntity(githubUserId: 7, login: "fixture", keychainAccountKey: "fixture")
        #expect(account.scopes.isEmpty)
    }

    @Test("Each authentication stages a separate identity-bound credential so disconnect cannot delete a replacement")
    func credentialVersions() {
        let first = session(id: 7, login: "first")
        let replacement = session(id: 7, login: "renamed")
        #expect(first.keychainAccountKey.hasPrefix("github-user:7:"))
        #expect(replacement.keychainAccountKey.hasPrefix("github-user:7:"))
        #expect(first.keychainAccountKey != replacement.keychainAccountKey)
    }

    @Test("Connecting an account keeps one active identity and reuses metadata by GitHub ID")
    func upsertAndActivation() throws {
        let context = try makeContext()
        let firstSession = session(id: 7, login: "first")
        let first = try GitHubAccountStore.upsert(firstSession, in: context)
        let second = try GitHubAccountStore.upsert(session(id: 8, login: "second"), in: context)
        #expect(!first.isActive && second.isActive)
        let originalID = first.id
        let updated = try GitHubAccountStore.upsert(session(id: 7, login: "renamed"), in: context)
        #expect(updated.id == originalID)
        #expect(updated.login == "renamed" && updated.keychainAccountKey.hasPrefix("github-user:7:"))
        #expect(updated.isActive && !second.isActive)
        #expect(updated.retiredKeychainAccountKeys == [firstSession.keychainAccountKey])
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 2)
        try GitHubAccountStore.activate(accountID: second.id, in: context)
        #expect(second.isActive && !updated.isActive)
        let audit = try context.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(audit.count == 4)
        #expect(audit.allSatisfy { $0.category == .authentication })
    }

    @Test("Reused login names never merge different GitHub identities")
    func stableIdentity() throws {
        let context = try makeContext()
        let original = try GitHubAccountStore.upsert(session(id: 7, login: "same-name"), in: context)
        let other = try GitHubAccountStore.upsert(session(id: 8, login: "same-name"), in: context)
        #expect(original.id != other.id)
        #expect(!original.isActive && other.isActive)
        #expect(original.keychainAccountKey.hasPrefix("github-user:7:"))
        #expect(other.keychainAccountKey.hasPrefix("github-user:8:"))
        try GitHubAccountStore.activate(accountID: original.id, in: context)
        #expect(original.isActive && !other.isActive)
    }

    @Test("Reauthentication migrates a legacy login alias without losing its cleanup reference")
    func legacyCredentialAlias() throws {
        let context = try makeContext()
        let old = GitHubAccountEntity(githubUserId: 7, login: "first", keychainAccountKey: "first")
        context.insert(old)
        try context.save()
        let updated = try GitHubAccountStore.upsert(session(id: 7, login: "renamed"), in: context)
        #expect(updated.id == old.id)
        #expect(updated.keychainAccountKey.hasPrefix("github-user:7:"))
        #expect(updated.retiredKeychainAccountKeys == ["first"])
    }

    @Test("Invalid identities and unknown selections do not deactivate existing accounts")
    func invalidInputs() throws {
        let context = try makeContext()
        let account = try GitHubAccountStore.upsert(session(id: 7, login: "first"), in: context)
        #expect(throws: (any Error).self) { try GitHubAccountStore.upsert(session(id: 0, login: ""), in: context) }
        #expect(throws: (any Error).self) { try GitHubAccountStore.activate(accountID: UUID(), in: context) }
        #expect(account.isActive)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 1)
    }

    @Test("A pre-cancelled authentication cannot persist metadata or audit events")
    func cancelledUpsert() async throws {
        let context = try makeContext()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            #expect(throws: CancellationError.self) { try GitHubAccountStore.upsert(session(id: 7, login: "first"), in: context) }
        }
        await task.value
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
    }

    private func makeContext() throws -> ModelContext {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        return container.mainContext
    }
    private func session(id: Int64, login: String) -> AuthenticatedGitHubSession {
        AuthenticatedGitHubSession(user: GitHubUserProfileDTO(id: id, login: login, name: "Fixture User"), scopes: [], authMethod: "pat")
    }
}
