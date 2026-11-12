import Foundation

public protocol WorkflowHistoryLoading: Sendable {
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage
}
