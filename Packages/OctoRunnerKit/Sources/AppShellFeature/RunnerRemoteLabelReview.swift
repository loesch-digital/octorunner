import CoreModels
import Foundation
import SwiftData
import SyncKit

@MainActor
struct RunnerRemoteLabelReview: Identifiable {
    let id = UUID()
    let accountLogin: String
    let githubLabels: [String]
    private let originalLabels: [String]
    private let runnerID: UUID
    private let configuration: LocalDotRunnerConfig
    private let account: RunnerSyncAccount

    init?(snapshot: RunnerSyncSnapshot, runner: RunnerEntity, account selected: GitHubAccountEntity) {
        let account = RunnerSyncAccount(selected)
        guard selected.isActive, snapshot.account == account,
              let configuration = LocalDotRunnerConfig(runner),
              snapshot.configurations[runner.id] == configuration,
              case .found(let remote, _) = snapshot.results[runner.id],
              remote.name == runner.name, remote.id == configuration.agentId,
              Set(remote.labelNames.map { $0.lowercased() }) != Set(runner.labels.map { $0.lowercased() }) else { return nil }
        self.configuration = configuration
        self.account = account
        accountLogin = selected.login
        runnerID = runner.id
        githubLabels = remote.labelNames
        originalLabels = runner.labels
    }

    func apply(in context: ModelContext) throws -> Bool {
        try Task.checkCancellation()
        let active = FetchDescriptor<GitHubAccountEntity>(predicate: #Predicate { $0.isActive })
        guard try context.fetch(active).first.map(RunnerSyncAccount.init) == account else { return false }
        let id = runnerID
        let descriptor = FetchDescriptor<RunnerEntity>(predicate: #Predicate { $0.id == id })
        guard let runner = try context.fetch(descriptor).first,
              LocalDotRunnerConfig(runner) == configuration, runner.labels == originalLabels else { return false }
        try context.transaction {
            runner.labels = githubLabels
            context.insert(AuditLogEntity(category: .configuration, title: "GitHub Runner Labels Adopted",
                summary: "Updated local labels for \(runner.name) from GitHub", actorAccountLogin: accountLogin,
                targetRunnerName: runner.name, previousValue: originalLabels.joined(separator: ", "),
                newValue: githubLabels.joined(separator: ", ")))
        }
        return true
    }
}
