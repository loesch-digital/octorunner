import CoreModels
import Foundation
import GitHubAPI
import SecurityKit
import SwiftData
import Testing
@testable import AppShellFeature

@MainActor
struct AuthCredentialIdentityTests {
    private static var containers: [ModelContainer] = []

    @Test("A reclaimed login cannot overwrite an old identity's token when authentication is cancelled after saving")
    func reclaimedLoginCancellation() async throws {
        let vault = KeychainVaultActor(servicePrefix: "octorunner-identity-\(UUID().uuidString)")
        try await vault.saveSecret("synthetic-old", account: "same-name")
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        let context = container.mainContext
        let old = GitHubAccountEntity(githubUserId: 7, login: "same-name", keychainAccountKey: "same-name")
        context.insert(old)
        try context.save()
        let transport = AuthIdentityTransport()
        let writer = CancellingIdentityWriter(vault: vault)
        let authenticator = GitHubOAuthActor(keychain: vault, transport: transport, tokenWriter: writer)
        let task = Task {
            await #expect(throws: CancellationError.self) {
                _ = try await authenticator.authenticateWithPersonalAccessToken("synthetic-new")
            }
        }
        await task.value
        #expect(try await vault.readSecret(account: old.keychainAccountKey) == "synthetic-old")
        let stagedKey = try #require(await writer.savedKey)
        #expect(stagedKey.hasPrefix("github-user:8:"))
        #expect(try await vault.readSecret(account: stagedKey) == nil)
        #expect(old.githubUserId == 7 && old.isActive)
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 1)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
        try await vault.deleteSecret(account: "same-name")
        try await vault.deleteSecret(account: stagedKey)
    }
}

private actor AuthIdentityTransport: GitHubActionsTransport {
    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        #expect(request.url == GitHubOAuthConfig.userProfileEndpoint)
        return GitHubActionsHTTPResponse(statusCode: 200, headers: [:],
            data: Data(#"{"id":8,"login":"same-name"}"#.utf8))
    }
}

private actor CancellingIdentityWriter: SecretWriting {
    private(set) var savedKey: String?
    let vault: KeychainVaultActor
    init(vault: KeychainVaultActor) { self.vault = vault }
    func saveSecret(_ secret: String, account: String, category: String) async throws {
        try await vault.saveSecret(secret, account: account, category: category)
        savedKey = account
        withUnsafeCurrentTask { $0?.cancel() }
    }
}
