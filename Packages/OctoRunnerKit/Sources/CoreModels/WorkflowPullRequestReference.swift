import Foundation

public struct WorkflowPullRequestReference: Codable, Sendable, Equatable, Identifiable {
    public let number: Int
    public let repository: String
    public var id: String { "\(repository)#\(number)" }
    public var url: URL { URL(string: "https://github.com/\(repository)/pull/\(number)")! }

    public init?(number: Int, repository: String) {
        guard number > 0, let slug = GitHubRepositorySlug(input: repository),
              slug.rawValue.caseInsensitiveCompare(repository) == .orderedSame else { return nil }
        self.number = number
        self.repository = slug.rawValue
    }

    private enum CodingKeys: String, CodingKey { case number, repository }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let number = try container.decode(Int.self, forKey: .number)
        let repository = try container.decode(String.self, forKey: .repository)
        guard let reference = Self(number: number, repository: repository) else {
            throw DecodingError.dataCorruptedError(forKey: .repository, in: container, debugDescription: "Invalid pull request reference")
        }
        self = reference
    }

    /// Revalidate data read from disk; synthesized Codable is not a validation boundary.
    public func validated(repository expected: String) -> Self? {
        guard repository.caseInsensitiveCompare(expected) == .orderedSame else { return nil }
        return Self(number: number, repository: expected)
    }
}
