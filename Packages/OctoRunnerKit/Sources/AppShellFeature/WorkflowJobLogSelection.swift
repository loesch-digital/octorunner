import CoreModels
import Foundation

struct WorkflowJobLogSelection: Hashable, Sendable, Identifiable {
    let detail: WorkflowRunDetailSelection
    let jobID: Int64
    let jobName: String
    var id: Self { self }
    var webURL: URL? {
        guard let slug = GitHubRepositorySlug(input: detail.source.repository), jobID > 0, detail.runID > 0 else { return nil }
        return URL(string: "https://github.com/\(slug.rawValue)/actions/runs/\(detail.runID)/job/\(jobID)")
    }
}
