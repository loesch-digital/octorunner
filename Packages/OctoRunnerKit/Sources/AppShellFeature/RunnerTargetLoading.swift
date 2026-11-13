import GitHubAPI

public protocol RunnerTargetLoading: Sendable {
    func readToken(for accountLogin: String) async throws -> String
    func fetchUserRepositories(token: String) async throws -> [GitHubRepositorySummaryDTO]
    func fetchUserOrganizations(token: String) async throws -> [GitHubOrganizationSummaryDTO]
}

extension GitHubRunnerProvisioningClient: RunnerTargetLoading {}
