import CoreModels
import Foundation

public struct WorkflowHistorySelection: Sendable, Hashable {
    public let accountID: Int64
    public let keychainAccountKey: String
    public let repository: String

    @MainActor
    static func managedRepositories(for runners: [RunnerEntity]) -> [String] {
        Set(runners.compactMap { runner -> String? in
            guard runner.scopeType != .organization else { return nil }
            return GitHubRepositorySlug(input: runner.scopeUrlString)?.rawValue
        }).sorted()
    }

    @MainActor
    static func configuredRepositories(for runners: [RunnerEntity], accountID: Int64, preferences: WorkflowHistoryPreferences) -> Set<String> {
        let added = preferences.validated().additionalRepositoriesByAccount[String(accountID)] ?? []
        return Set(managedRepositories(for: runners) + added)
    }

    public init(accountID: Int64, keychainAccountKey: String, repository: String) {
        self.accountID = accountID
        self.keychainAccountKey = keychainAccountKey
        self.repository = repository
    }
}
