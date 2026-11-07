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
