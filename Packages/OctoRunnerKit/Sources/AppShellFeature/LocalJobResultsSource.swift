import CoreModels
import SwiftData
import SwiftUI

/// One query per presentation root, rather than a history fetch per runner row.
public struct LocalJobResultsSource<Content: View>: View {
    @Query(filter: #Predicate<JobRunEntity> { $0.sourceRaw == "github" }) private var jobs: [JobRunEntity]
    @Query(filter: #Predicate<GitHubAccountEntity> { $0.isActive }) private var accounts: [GitHubAccountEntity]
    @Query private var runners: [RunnerEntity]
    @Environment(AppPreferencesStore.self) private var preferences
    private let content: (LocalJobResults) -> Content

    public init(@ViewBuilder content: @escaping (LocalJobResults) -> Content) { self.content = content }

    public var body: some View {
        content(LocalJobResults(entries: jobs.map(WorkflowHistoryEntry.init), runners: runners,
            accountID: accounts.count == 1 ? accounts.first?.githubUserId : nil,
            reviewed: preferences.reviewedJobFailures))
    }
}
