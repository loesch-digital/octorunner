import Foundation

struct WorkflowRunDetailRequest: Equatable {
    let selection: WorkflowRunDetailSelection
    let refreshTicket: UUID
}
