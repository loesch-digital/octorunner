import Foundation
import CoreModels

struct WorkflowRunDetailSelection: Hashable, Sendable, Identifiable {
    let source: WorkflowHistorySelection
    let runID: Int64
    let attempt: Int
    var id: Self { self }

    init(source: WorkflowHistorySelection, runID: Int64, attempt: Int) {
        self.source = source; self.runID = runID; self.attempt = attempt
    }

    init?(entry: WorkflowHistoryEntry, source: WorkflowHistorySelection) {
        guard entry.accountID == source.accountID, source.accountID > 0,
              !source.keychainAccountKey.isEmpty, entry.githubRunID > 0,
              let attempt = entry.attempt, attempt > 0,
              let slug = GitHubRepositorySlug(input: source.repository),
              slug.rawValue == entry.repository.lowercased() else { return nil }
        self.init(source: source, runID: entry.githubRunID, attempt: attempt)
    }
}
