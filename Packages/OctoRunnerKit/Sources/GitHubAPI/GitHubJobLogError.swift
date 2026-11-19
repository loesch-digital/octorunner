public enum GitHubJobLogError: Error, Sendable, Equatable {
    case invalidRedirect
    case unsupportedContent
}
