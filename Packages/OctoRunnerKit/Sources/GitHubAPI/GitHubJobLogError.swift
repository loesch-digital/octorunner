public enum GitHubJobLogError: Error, Sendable, Equatable {
    case invalidRedirect(rateLimit: GitHubRateLimitSnapshot? = nil)
    case unsupportedContent(rateLimit: GitHubRateLimitSnapshot? = nil)
    case downloadFailed(statusCode: Int?, rateLimit: GitHubRateLimitSnapshot? = nil)

    public var rateLimit: GitHubRateLimitSnapshot? {
        switch self {
        case .invalidRedirect(let rate), .unsupportedContent(let rate), .downloadFailed(_, let rate): rate
        }
    }
}
