import Foundation
import SwiftData

@Model
public final class JobRunEntity {
    public var id: UUID = UUID()
    public var githubRunId: Int64 = 0
    public var workflowName: String = ""
    public var repositoryFullName: String = ""
    public var branchName: String = ""
    public var commitSha: String = ""
    public var statusRaw: String = "completed"
    public var startedAt: Date = Date.now
    public var durationSeconds: Double = 0
    public var runner: RunnerEntity?

    // Additive fields keep existing stores and their original timestamps intact.
    // A workflow record is distinct from its matrix jobs and retry attempts.
    public var recordKindRaw: String = "workflow"
    public var sourceRaw: String = "legacy"
    public var accountGitHubUserID: Int64? = nil
    public var githubJobId: Int64? = nil
    public var runAttempt: Int? = nil
    public var jobName: String? = nil
    public var conclusion: String? = nil
    public var createdAt: Date? = nil
    public var actualStartedAt: Date? = nil
    public var completedAt: Date? = nil
    public var event: String? = nil
    public var htmlURLString: String? = nil
    public var githubRunnerIDSnapshot: Int64? = nil
    public var runnerNameSnapshot: String? = nil
    public var observedAt: Date? = nil
    public var jobDetailsComplete: Bool = false

    /// Only an observed start and completion define a remote duration. Legacy
    /// durations remain available without inventing a conclusion or attempt.
    public var measuredDurationSeconds: Double? {
        if sourceRaw == "legacy" {
            return durationSeconds.isFinite && durationSeconds >= 0 ? durationSeconds : nil
        }
        guard statusRaw == "completed", let actualStartedAt, let completedAt else { return nil }
        let duration = completedAt.timeIntervalSince(actualStartedAt)
        return duration.isFinite && duration >= 0 ? duration : nil
    }

    public init(
        id: UUID = UUID(),
        githubRunId: Int64,
        workflowName: String,
        repositoryFullName: String,
        branchName: String,
        commitSha: String,
        statusRaw: String = "completed",
        startedAt: Date = .now,
        durationSeconds: Double = 0,
        runner: RunnerEntity? = nil
    ) {
        self.id = id
        self.githubRunId = githubRunId
        self.workflowName = workflowName
        self.repositoryFullName = repositoryFullName
        self.branchName = branchName
        self.commitSha = commitSha
        self.statusRaw = statusRaw
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.runner = runner
    }
}
