import Foundation

public struct GitHubActionsPage<Element: Sendable>: Sendable {
    public let items: [Element]
    public let nextPage: URL?
    public let totalCount: Int

    public init(items: [Element], nextPage: URL?, totalCount: Int) {
        self.items = items
        self.nextPage = nextPage
        self.totalCount = totalCount
    }
}
