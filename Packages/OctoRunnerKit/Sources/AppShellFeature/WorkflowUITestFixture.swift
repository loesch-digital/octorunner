#if DEBUG
import CoreModels
import Foundation
import GitHubAPI
import SecurityKit
import SwiftData
import SwiftUI

extension EnvironmentValues {
    @Entry var workflowUITestFixture: WorkflowUITestFixture?
}

@_spi(Testing) public struct WorkflowUITestFixture: Sendable {
    let directory: URL
    private static let repository = "https://github.com/example/repo"

    public static let directoryKey = "OCTORUNNER_WORKFLOW_UI_TEST_DIRECTORY"

    public init(directory: URL) {
        self.directory = directory
    }

    @MainActor public func container() throws -> ModelContainer {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let context = container.mainContext
        let account = GitHubAccountEntity(githubUserId: 42, login: "fixture", keychainAccountKey: "fixture")
        let runner = RunnerEntity(
            name: "Fixture Runner",
            scopeUrl: URL(string: Self.repository)!,
            status: .busy,
            workDirectory: directory,
            rootDirectoryPath: directory.path(percentEncoded: false),
            isImportedLocal: true
        )
        runner.githubRunnerId = 31
        context.insert(account)
        context.insert(runner)
        try context.save()
        return container
    }

    @MainActor public func dashboard(preferences: AppPreferencesStore) -> some View {
        LocalJobResultsSource { results in MainShellView(jobResults: results) }
            .environment(preferences)
            .environment(\.workflowUITestFixture, self)
            .environment(\.locale, preferences.language.locale)
            .frame(minWidth: 960, minHeight: 680)
    }

    @MainActor func detailModel(rateBudget: WorkflowHistoryRateBudget) -> WorkflowRunDetailModel {
        WorkflowRunDetailModel(client: GitHubActionsClient(transport: self), secrets: self, rateBudget: rateBudget)
    }

    private func payload() throws -> Data {
        try Data(contentsOf: directory.appending(path: "history.json"))
    }

    private struct Observation: Decodable {
        let run: GitHubWorkflowRunDTO
        let jobs: [GitHubWorkflowJobDTO]
    }
}

extension WorkflowUITestFixture: WorkflowHistoryLoading {
    public func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let observations = try decoder.decode([Observation].self, from: payload())
        return WorkflowHistoryPage(runs: observations.map { .init(run: $0.run, jobs: $0.jobs) }, nextPage: nil,
                                   rateLimit: nil, observedAt: .now)
    }
}

extension WorkflowUITestFixture: GitHubActionsTransport, SecretReading {
    public func readSecret(account: String, category: String) async throws -> String? { "fixture" }

    public func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        guard let components = request.url?.pathComponents,
              let runs = components.firstIndex(of: "runs"),
              components.indices.contains(runs + 1),
              let id = Int64(components[runs + 1]),
              let observations = try JSONSerialization.jsonObject(with: payload()) as? [[String: Any]],
              let match = observations.first(where: { ($0["run"] as? [String: Any])?["id"] as? Int64 == id }),
              let run = match["run"], let jobs = match["jobs"] as? [[String: Any]] else {
            return .init(statusCode: 404, headers: [:], data: Data())
        }
        let data = try JSONSerialization.data(withJSONObject: components.last == "jobs"
            ? ["total_count": jobs.count, "jobs": jobs] : run)
        return .init(statusCode: 200, headers: [:], data: data)
    }
}
#endif
