import GitHubAPI

public struct WorkflowRunDetails: Sendable {
    public let run: GitHubWorkflowRunDTO
    /// nil means details were not fetched; [] means the full response was empty.
    public let jobs: [GitHubWorkflowJobDTO]?

    public init(run: GitHubWorkflowRunDTO, jobs: [GitHubWorkflowJobDTO]?) {
        self.run = run
        self.jobs = jobs
    }
}
