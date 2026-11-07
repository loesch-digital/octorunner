import Foundation
import SecurityKit
import Testing

@Suite("SecurityKit & Keychain Vault Tests")
struct SecurityKitTests {
    @Test("KeychainVaultActor add-or-update, read, and delete lifecycle")
    func keychainAddUpdateAndDeleteLifecycle() async throws {
        let vault = KeychainVaultActor(servicePrefix: "io.octorunner.macos.tests.\(UUID().uuidString)")
        let account = "test-user"

        let initial = try await vault.readSecret(account: account)
        #expect(initial == nil)

        try await vault.saveSecret("gho_initial_token_123", account: account)
        let saved = try await vault.readSecret(account: account)
        #expect(saved == "gho_initial_token_123")

        // Update existing secret (tests errSecDuplicateItem -> SecItemUpdate path)
        try await vault.saveSecret("gho_updated_token_456", account: account)
        let updated = try await vault.readSecret(account: account)
        #expect(updated == "gho_updated_token_456")

        try await vault.deleteSecret(account: account)
        let afterDelete = try await vault.readSecret(account: account)
        #expect(afterDelete == nil)
    }

    @Test("KeychainVaultActor isolates multiple accounts under the same service prefix")
    func keychainMultipleAccountIsolation() async throws {
        let vault = KeychainVaultActor(servicePrefix: "io.octorunner.macos.tests.\(UUID().uuidString)")

        try await vault.saveSecret("token-alpha", account: "user-alpha")
        try await vault.saveSecret("token-beta", account: "user-beta")

        #expect(try await vault.readSecret(account: "user-alpha") == "token-alpha")
        #expect(try await vault.readSecret(account: "user-beta") == "token-beta")

        try await vault.deleteSecret(account: "user-alpha")
        #expect(try await vault.readSecret(account: "user-alpha") == nil)
        #expect(try await vault.readSecret(account: "user-beta") == "token-beta")

        try await vault.deleteSecret(account: "user-beta")
    }

    @Test("KeychainError equatable conformance and OSStatus mapping")
    func keychainErrorEquatable() {
        let statusError = KeychainError.unexpectedStatus(-25300)
        #expect(statusError == KeychainError.unexpectedStatus(-25300))
        #expect(KeychainError.invalidDataEncoding != statusError)
        #expect(KeychainError.interactionNotAllowed != statusError)
        #expect(!statusError.localizedDescription.isEmpty)
        #expect(!KeychainError.interactionNotAllowed.localizedDescription.isEmpty)
    }
}
