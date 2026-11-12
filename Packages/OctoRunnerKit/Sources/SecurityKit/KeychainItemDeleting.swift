import Security

/// A synchronous Security boundary; the vault invokes it exclusively on its actor.
protocol KeychainItemDeleting: Sendable {
    func delete(service: String, account: String, useDataProtection: Bool) -> OSStatus
}
