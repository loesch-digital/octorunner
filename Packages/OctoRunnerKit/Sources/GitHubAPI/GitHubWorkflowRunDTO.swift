import Foundation

public struct GitHubWorkflowRunDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let name: String?
    public let headBranch: String?
    public let headSHA: String?
    public let status: String?
    public let conclusion: String?
    public let runAttempt: Int?
    public let createdAt: Date?
    public let startedAt: Date?
    public let updatedAt: Date?
    public let event: String?
    public let htmlURL: URL?

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, event
        case headBranch = "head_branch", headSHA = "head_sha", runAttempt = "run_attempt"
        case createdAt = "created_at", startedAt = "run_started_at", updatedAt = "updated_at", htmlURL = "html_url"
    }
}
