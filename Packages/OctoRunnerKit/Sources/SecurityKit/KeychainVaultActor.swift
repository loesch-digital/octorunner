import CoreModels
import Foundation
import Security

/// Actor-isolated Keychain wrapper compliant with `swift-security-expert`:
/// - All `SecItem*` calls execute off `@MainActor` inside this actor.
/// - Exhaustive `OSStatus` switch covering `errSecSuccess`, `errSecDuplicateItem`, `errSecItemNotFound`, `errSecInteractionNotAllowed`.
/// - Uses Add-or-Update pattern with fresh dictionaries per call.
/// - Uses `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly` for background daemon/runner access.
/// - Targets macOS Data Protection Keychain (`kSecUseDataProtectionKeychain: true`, TN3137) with graceful fallback when running ad-hoc without a provisioning profile (`errSecMissingEntitlement`).
public actor KeychainVaultActor: SecretReading, SecretWriting, SecretDeleting {
    private let servicePrefix: String
    private let itemDeleter: any KeychainItemDeleting

    public init(servicePrefix: String = "io.octorunner.macos") {
        self.servicePrefix = servicePrefix
        itemDeleter = SystemKeychainItemDeleter()
    }

    init(servicePrefix: String, itemDeleter: any KeychainItemDeleting) {
        self.servicePrefix = servicePrefix
        self.itemDeleter = itemDeleter
    }

    public func saveSecret(_ secret: String, account: String, category: String = "github-oauth") throws {
        try Task.checkCancellation()
        guard let data = secret.data(using: .utf8) else {
            throw KeychainError.invalidDataEncoding
        }
        let service = "\(servicePrefix).\(category)"

        let status = performSave(data: data, service: service, account: account, useDataProtection: true)
        let resolvedStatus: OSStatus
        if status == errSecMissingEntitlement {
            resolvedStatus = performSave(data: data, service: service, account: account, useDataProtection: false)
        } else {
            resolvedStatus = status
        }

        switch resolvedStatus {
        case errSecSuccess:
            return
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        default:
            throw KeychainError.unexpectedStatus(resolvedStatus)
        }
    }

    public func readSecret(account: String, category: String = "github-oauth") throws -> String? {
        let service = "\(servicePrefix).\(category)"

        var item: CFTypeRef?
        var status = performRead(service: service, account: account, useDataProtection: true, result: &item)
        if status == errSecMissingEntitlement || status == errSecItemNotFound {
            status = performRead(service: service, account: account, useDataProtection: false, result: &item)
        }

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let secret = String(data: data, encoding: .utf8) else {
                throw KeychainError.invalidDataEncoding
            }
            return secret
        case errSecItemNotFound:
            return nil
        case errSecInteractionNotAllowed:
            throw KeychainError.interactionNotAllowed
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    public func deleteSecret(account: String, category: String = "github-oauth") throws {
        let service = "\(servicePrefix).\(category)"

        // Reads support both macOS implementations. Removing only the preferred
        // copy could expose an older fallback credential on the next read.
        let modern = performDelete(service: service, account: account, useDataProtection: true)
        let legacy = performDelete(service: service, account: account, useDataProtection: false)
        for status in [modern == errSecMissingEntitlement ? errSecItemNotFound : modern, legacy] {
            switch status {
            case errSecSuccess, errSecItemNotFound:
                continue
            case errSecInteractionNotAllowed:
                throw KeychainError.interactionNotAllowed
            default:
                throw KeychainError.unexpectedStatus(status)
            }
        }
    }

    // MARK: - Private Query Helpers (Fresh Dictionary Per Call)

    private func performSave(data: Data, service: String, account: String, useDataProtection: Bool) -> OSStatus {
        var addQuery: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData: data
        ]
        if useDataProtection {
            addQuery[kSecUseDataProtectionKeychain] = true
        }

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        switch addStatus {
        case errSecDuplicateItem:
            var searchQuery: [CFString: Any] = [
                kSecClass: kSecClassGenericPassword,
                kSecAttrService: service,
                kSecAttrAccount: account
            ]
            if useDataProtection {
                searchQuery[kSecUseDataProtectionKeychain] = true
            }
            let attributesToUpdate: [CFString: Any] = [
                kSecValueData: data,
                kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            ]
            return SecItemUpdate(searchQuery as CFDictionary, attributesToUpdate as CFDictionary)
        default:
            return addStatus
        }
    }

    private func performRead(
        service: String,
        account: String,
        useDataProtection: Bool,
        result: inout CFTypeRef?
    ) -> OSStatus {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        if useDataProtection {
            query[kSecUseDataProtectionKeychain] = true
        }
        return SecItemCopyMatching(query as CFDictionary, &result)
    }

    private func performDelete(service: String, account: String, useDataProtection: Bool) -> OSStatus {
        itemDeleter.delete(service: service, account: account, useDataProtection: useDataProtection)
    }
}
