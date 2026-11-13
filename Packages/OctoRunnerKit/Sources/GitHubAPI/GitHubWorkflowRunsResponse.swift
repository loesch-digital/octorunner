struct GitHubWorkflowRunsResponse: Decodable {
    let totalCount: Int
    let workflowRuns: [GitHubWorkflowRunDTO]
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count", workflowRuns = "workflow_runs"
    }
}
