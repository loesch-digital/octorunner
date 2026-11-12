import Foundation

/// Immutable history data can leave the model context without carrying models.
public struct WorkflowHistoryEntry: Sendable, Identifiable {
    public let id: UUID
    public let githubRunID: Int64
    public let githubJobID: Int64?
    public let accountID: Int64?
    public let repository: String
    public let attempt: Int?
    public let recordKind: String
    public let workflowName: String
    public let jobName: String?
    public let branch: String
    public let commitSHA: String
    public let status: String
    public let conclusion: String?
    public let createdAt: Date?
    public let startedAt: Date?
    public let completedAt: Date?
    public let durationSeconds: Double?
    public let runnerID: Int64?
    public let runnerName: String?
    public let event: String?
    public let htmlURL: URL?
    public let observedAt: Date?

    @MainActor
    public init(_ entity: JobRunEntity) {
        id = entity.id
        githubRunID = entity.githubRunId
        githubJobID = entity.githubJobId
        accountID = entity.accountGitHubUserID
        repository = entity.repositoryFullName
        attempt = entity.runAttempt
        recordKind = entity.recordKindRaw
        workflowName = entity.workflowName
        jobName = entity.jobName
        branch = entity.branchName
        commitSHA = entity.commitSha
        status = entity.statusRaw
        conclusion = entity.conclusion
        createdAt = entity.createdAt
        startedAt = entity.sourceRaw == "legacy" ? entity.startedAt : entity.actualStartedAt
        completedAt = entity.completedAt
        durationSeconds = entity.measuredDurationSeconds
        runnerID = entity.githubRunnerIDSnapshot ?? entity.runner?.githubRunnerId
        runnerName = entity.runnerNameSnapshot ?? entity.runner?.name
        event = entity.event
        htmlURL = entity.htmlURLString.flatMap(URL.init(string:))
        observedAt = entity.observedAt
    }

    public func isFresh(at now: Date, maxAge: TimeInterval = 90) -> Bool {
        guard let observedAt else { return false }
        let age = now.timeIntervalSince(observedAt)
        return age >= -5 && age <= maxAge
    }

    var runKey: String { "\(accountID.map(String.init) ?? "legacy")|\(repository.lowercased())|\(githubRunID)" }
}
