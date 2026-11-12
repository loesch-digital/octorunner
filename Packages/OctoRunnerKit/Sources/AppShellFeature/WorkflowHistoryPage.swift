import Foundation
import GitHubAPI

public struct WorkflowHistoryPage: Sendable {
    public let runs: [WorkflowRunDetails]
    public let nextPage: URL?
    public let rateLimit: GitHubRateLimitSnapshot?
    public let observedAt: Date

    public init(runs: [WorkflowRunDetails], nextPage: URL?, rateLimit: GitHubRateLimitSnapshot?, observedAt: Date) {
        self.runs = runs
        self.nextPage = nextPage
        self.rateLimit = rateLimit
        self.observedAt = observedAt
    }
}
