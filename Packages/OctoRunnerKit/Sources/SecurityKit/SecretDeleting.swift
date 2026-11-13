public protocol SecretDeleting: Sendable {
    func deleteSecret(account: String, category: String) async throws
}
