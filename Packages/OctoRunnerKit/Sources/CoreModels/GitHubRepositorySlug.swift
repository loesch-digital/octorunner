import Foundation

/// Validated GitHub repository identity, never a credential-bearing URL.
public struct GitHubRepositorySlug: Hashable, Sendable {
    private static let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.".utf8)

    public let rawValue: String

    public init?(input: String) {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug: String
        if input.contains("://") {
            guard let url = URLComponents(string: input), url.scheme == "https",
                  url.host?.lowercased() == "github.com", url.port == nil || url.port == 443,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else { return nil }
            let path = url.percentEncodedPath
            guard path.hasPrefix("/"), !path.contains("%") else { return nil }
            slug = String(path.dropFirst().dropLast(path.hasSuffix("/") ? 1 : 0))
        } else {
            slug = input
        }
        self.init(slug: slug)
    }

    package init?(slug: String) {
        let parts = slug.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({
            !$0.isEmpty && $0 != "." && $0 != ".." && $0.utf8.allSatisfy(Self.allowed.contains)
        }) else { return nil }
        rawValue = slug.lowercased()
    }
}
