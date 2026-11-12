public protocol SecretWriting: Sendable {
    func saveSecret(_ secret: String, account: String, category: String) async throws
}
