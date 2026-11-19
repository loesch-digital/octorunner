import CoreModels

public struct GitHubJobLogResult: Sendable {
    public let snapshot: WorkflowJobLogSnapshot
    /// Metadata from api.github.com, never the signed download host.
    public let rateLimit: GitHubRateLimitSnapshot?
}
