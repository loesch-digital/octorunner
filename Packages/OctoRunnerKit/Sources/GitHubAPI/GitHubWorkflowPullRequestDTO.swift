import Foundation

/// Both workflow-run references and commit-associated PR responses include a base repo URL.
public struct GitHubWorkflowPullRequestDTO: Codable, Sendable, Equatable {
    public let number: Int
    public let base: Branch?

    public struct Branch: Codable, Sendable, Equatable {
        public let repo: Repository?
    }

    public struct Repository: Codable, Sendable, Equatable {
        public let url: URL?
    }
}
