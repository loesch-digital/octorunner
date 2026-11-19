import Foundation

public struct GitHubWorkflowJobDTO: Codable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let runID: Int64
    public let runAttempt: Int?
    public let name: String
    public let status: String
    public let conclusion: String?
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    public let runnerID: Int64?
    public let runnerName: String?
    public let labels: [String]?
    public let htmlURL: URL?
    public let steps: [GitHubWorkflowStepDTO]?

    public var hasValidStepIdentities: Bool {
        guard let steps else { return true }
        return steps.allSatisfy { $0.number > 0 } && Set(steps.map(\.number)).count == steps.count
    }

    enum CodingKeys: String, CodingKey {
        case id, name, status, conclusion, labels, steps
        case runID = "run_id", createdAt = "created_at", startedAt = "started_at", completedAt = "completed_at"
        case runAttempt = "run_attempt"
        case runnerID = "runner_id", runnerName = "runner_name", htmlURL = "html_url"
    }
}
