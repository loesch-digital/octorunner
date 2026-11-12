import CoreModels
import Foundation
import GitHubAPI
import SecurityKit
import SwiftData
import Testing
@testable import AppShellFeature

@MainActor
struct AccountSessionControllerTests {
    private static var containers: [ModelContainer] = []
    private enum SaveFailure: Error { case fixture }

    @Test("A failed disconnect save restores the account and removes pending success audit while preserving unrelated edits")
    func failedMetadataSave() async throws {
        let context = try makeContext()
        let account = addAccount(to: context)
        let other = GitHubAccountEntity(githubUserId: 8, login: "other", keychainAccountKey: "other-key", isActive: false)
        context.insert(other)
        try context.save()
        other.displayName = "Pending unrelated edit"
        let controller = AccountSessionController(secrets: AccountDeletionFixture(), save: { _ in throw SaveFailure.fixture })
        let id = account.id
        #expect(!(await controller.disconnect(accountID: id, in: context)))
        #expect(controller.error == .metadataPersistenceFailed)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 2)
        #expect(try context.fetch(FetchDescriptor<GitHubAccountEntity>()).contains { $0.id == id })
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
        #expect(other.displayName == "Pending unrelated edit")
    }

    @Test("Reclaiming a legacy login keeps its disabled credential reachable for scoped cleanup")
    func reclaimedLegacyCleanup() async throws {
        let context = try makeContext()
        let old = GitHubAccountEntity(githubUserId: 7, login: "same-name", keychainAccountKey: "same-name")
        context.insert(old)
        try context.save()
        let new = try GitHubAccountStore.upsert(AuthenticatedGitHubSession(
            user: GitHubUserProfileDTO(id: 8, login: "same-name"), scopes: [], authMethod: "pat"), in: context)
        #expect(old.keychainAccountKey.isEmpty)
        #expect(old.retiredKeychainAccountKeys == ["same-name"])
        let deleter = AccountDeletionFixture()
        let controller = AccountSessionController(secrets: deleter)
        #expect(await controller.disconnect(accountID: old.id, in: context))
        #expect(await deleter.keys == ["same-name"])
        #expect(new.isActive && new.keychainAccountKey.hasPrefix("github-user:8:"))
    }

    @Test("Disconnect removes current and retired credentials before metadata and success audit")
    func disconnect() async throws {
        let context = try makeContext()
        let account = GitHubAccountEntity(githubUserId: 7, login: "fixture", keychainAccountKey: "version-current")
        account.retiredKeychainAccountKeys = ["legacy", "shared", "version-current"]
        let other = GitHubAccountEntity(githubUserId: 8, login: "other", keychainAccountKey: "shared", isActive: false)
        context.insert(account); context.insert(other); try context.save()
        let deleter = AccountDeletionFixture()
        let controller = AccountSessionController(secrets: deleter)
        #expect(await controller.disconnect(accountID: account.id, in: context))
        #expect(await deleter.keys == ["legacy", "version-current"])
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 1)
        #expect(try context.fetch(FetchDescriptor<GitHubAccountEntity>()).first?.id == other.id)
        let audit = try #require(context.fetch(FetchDescriptor<AuditLogEntity>()).first)
        #expect(audit.category == .authentication)
        #expect(audit.severity == .warning)
        #expect(controller.error == nil && !controller.isBusy)
    }

    @Test("A Keychain failure keeps account metadata and never records false sign-out success")
    func failure() async throws {
        let context = try makeContext()
        let account = addAccount(to: context)
        try context.save()
        let controller = AccountSessionController(secrets: AccountDeletionFixture(fails: true))
        #expect(!(await controller.disconnect(accountID: account.id, in: context)))
        #expect(controller.error == .credentialDeletionFailed)
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
        #expect(account.isActive)
    }

    @Test("A cancelled disconnect never touches SwiftData after credential deletion completes")
    func cancellation() async throws {
        let context = try makeContext()
        let account = addAccount(to: context)
        try context.save()
        let deleter = AccountDeletionFixture(gated: true)
        let controller = AccountSessionController(secrets: deleter)
        let id = account.id
        let task = Task { await controller.disconnect(accountID: id, in: context) }
        await deleter.waitUntilEntered()
        #expect(!(await controller.disconnect(accountID: id, in: context)))
        task.cancel()
        await deleter.release()
        #expect(!(await task.value))
        #expect(await deleter.keys == ["old-version"])
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
        #expect(controller.error == nil && !controller.isBusy)
    }

    @Test("A replacement login during deletion survives with its new credential reference")
    func replacementLogin() async throws {
        let context = try makeContext()
        let account = addAccount(to: context)
        try context.save()
        let deleter = AccountDeletionFixture(gated: true)
        let controller = AccountSessionController(secrets: deleter)
        let id = account.id
        let task = Task { await controller.disconnect(accountID: id, in: context) }
        await deleter.waitUntilEntered()
        account.keychainAccountKey = "new-version"
        account.connectedAt = account.connectedAt.addingTimeInterval(1)
        try context.save()
        await deleter.release()
        #expect(!(await task.value))
        #expect(controller.error == .accountChanged)
        #expect(account.keychainAccountKey == "new-version" && account.isActive)
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
    }

    private func makeContext() throws -> ModelContext {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        return container.mainContext
    }
    private func addAccount(to context: ModelContext) -> GitHubAccountEntity {
        let account = GitHubAccountEntity(githubUserId: 7, login: "fixture", keychainAccountKey: "old-version")
        context.insert(account)
        return account
    }
}

private actor AccountDeletionFixture: SecretDeleting {
    let fails: Bool
    let gated: Bool
    private(set) var keys: [String] = []
    private var gate: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?
    init(fails: Bool = false, gated: Bool = false) { self.fails = fails; self.gated = gated }
    func deleteSecret(account: String, category: String) async throws {
        #expect(category == "github-oauth")
        keys.append(account)
        if gated { await withCheckedContinuation { gate = $0; started?.resume(); started = nil } }
        if fails { throw KeychainError.interactionNotAllowed }
    }
    func waitUntilEntered() async {
        if gate != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func release() { gate?.resume(); gate = nil }
}
