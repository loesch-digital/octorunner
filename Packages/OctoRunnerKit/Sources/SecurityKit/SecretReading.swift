public protocol SecretReading: Sendable {
    func readSecret(account: String, category: String) async throws -> String?
}
