import Foundation
import Security

struct SystemKeychainItemDeleter: KeychainItemDeleting {
    func delete(service: String, account: String, useDataProtection: Bool) -> OSStatus {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if useDataProtection { query[kSecUseDataProtectionKeychain] = true }
        return SecItemDelete(query as CFDictionary)
    }
}
