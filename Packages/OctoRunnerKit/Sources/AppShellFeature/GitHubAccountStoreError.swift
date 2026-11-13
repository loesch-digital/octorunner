public enum GitHubAccountStoreError: Error, Equatable, Sendable {
    case invalidIdentity
    case accountNotFound
    case reauthenticationRequired
}
