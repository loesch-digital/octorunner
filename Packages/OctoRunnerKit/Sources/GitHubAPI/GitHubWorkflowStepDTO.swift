import CoreModels
import Foundation

public struct GitHubWorkflowStepDTO: Codable, Sendable, Equatable {
    public let number: Int
    public let name: String
    public let status: String
    public let conclusion: String?
    public let startedAt: Date?
    public let completedAt: Date?

    enum CodingKeys: String, CodingKey {
        case number, name, status, conclusion
        case startedAt = "started_at", completedAt = "completed_at"
    }

    public var snapshot: WorkflowJobStep {
        WorkflowJobStep(number: number, name: name, status: status, conclusion: conclusion, startedAt: startedAt, completedAt: completedAt)
    }
}
