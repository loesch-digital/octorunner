struct GitHubWorkflowJobsResponse: Decodable {
    let totalCount: Int
    let jobs: [GitHubWorkflowJobDTO]
    enum CodingKeys: String, CodingKey {
        case totalCount = "total_count", jobs
    }
}
