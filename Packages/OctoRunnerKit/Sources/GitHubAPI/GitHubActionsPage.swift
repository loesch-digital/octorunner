import Foundation

public struct GitHubActionsPage<Element: Sendable>: Sendable {
    public let items: [Element]
    public let nextPage: URL?
    public let totalCount: Int
    public let rateLimit: GitHubRateLimitSnapshot?

    public init(items: [Element], nextPage: URL?, totalCount: Int, rateLimit: GitHubRateLimitSnapshot? = nil) {
        self.items = items
        self.nextPage = nextPage
        self.totalCount = totalCount
        self.rateLimit = rateLimit
    }
}
