import Foundation

struct WorkflowHistoryRequest: Hashable {
    let account: WorkflowHistorySelection?
    let sources: [WorkflowHistorySelection]
    let selectedRepository: String
    let isActive: Bool
    let refreshInterval: Int
    let ticket: UUID
}
