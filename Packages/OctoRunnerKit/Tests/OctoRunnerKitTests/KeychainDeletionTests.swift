import Foundation
import Security
@testable import SecurityKit
import Synchronization
import Testing

struct KeychainDeletionTests {
    @Test("A queued cancelled save does not leave a credential behind")
    func cancelledSave() async throws {
        let vault = KeychainVaultActor(servicePrefix: "io.octorunner.macos.tests.\(UUID())")
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await #expect(throws: CancellationError.self) { try await vault.saveSecret("synthetic-fixture", account: "fixture") }
        }
        await task.value
        #expect(try await vault.readSecret(account: "fixture") == nil)
        try await vault.deleteSecret(account: "fixture")
    }

    @Test("Logout removes both modern and legacy copies of exactly one credential")
    func deletesBothCopies() async throws {
        let fixture = DeletionFixture(modern: errSecSuccess, legacy: errSecSuccess)
        let vault = KeychainVaultActor(servicePrefix: "synthetic-service", itemDeleter: fixture)
        try await vault.deleteSecret(account: "fixture-user", category: "github-oauth")
        let calls = fixture.calls.withLock { $0 }
        #expect(calls.count == 2)
        #expect(calls.map(\.useDataProtection) == [true, false])
        #expect(calls.allSatisfy { $0.service == "synthetic-service.github-oauth" && $0.account == "fixture-user" })
    }

    @Test("Missing modern item or ad-hoc entitlement still clears the legacy copy", arguments: [errSecItemNotFound, errSecMissingEntitlement])
    func legacyFallback(status: OSStatus) async throws {
        let fixture = DeletionFixture(modern: status, legacy: errSecSuccess)
        let vault = KeychainVaultActor(servicePrefix: "synthetic-service", itemDeleter: fixture)
        try await vault.deleteSecret(account: "fixture-user")
        #expect(fixture.calls.withLock { $0.count } == 2)
    }

    @Test("A failure in either store remains an error after attempting scoped cleanup", arguments: [true, false])
    func errorsAreNotSuccess(modernFails: Bool) async {
        let fixture = DeletionFixture(modern: modernFails ? errSecInteractionNotAllowed : errSecSuccess,
            legacy: modernFails ? errSecSuccess : errSecAuthFailed)
        let vault = KeychainVaultActor(servicePrefix: "synthetic-service", itemDeleter: fixture)
        await #expect(throws: modernFails ? KeychainError.interactionNotAllowed : KeychainError.unexpectedStatus(errSecAuthFailed)) {
            try await vault.deleteSecret(account: "fixture-user")
        }
        #expect(fixture.calls.withLock { $0.count } == 2)
    }
}

private final class DeletionFixture: KeychainItemDeleting {
    struct Call { let service: String; let account: String; let useDataProtection: Bool }
    let modern: OSStatus
    let legacy: OSStatus
    let calls = Mutex<[Call]>([])
    init(modern: OSStatus, legacy: OSStatus) { self.modern = modern; self.legacy = legacy }
    func delete(service: String, account: String, useDataProtection: Bool) -> OSStatus {
        calls.withLock { $0.append(Call(service: service, account: account, useDataProtection: useDataProtection)) }
        return useDataProtection ? modern : legacy
    }
}
