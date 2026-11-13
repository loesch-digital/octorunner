public enum GitHubActionsError: Error, Sendable, Equatable {
    case invalidRepository
    case invalidPagination
    case invalidResponse
    case invalidRunAttempt
    case invalidToken
    case httpStatus(Int, rateLimit: GitHubRateLimitSnapshot? = nil)
}
