import CoreModels
import Foundation
import SwiftData
import SyncKit

@MainActor
struct RunnerRemoteLabelUpdate: Identifiable {
    let id = UUID()
    let selection: RunnerSyncAccount
    let configuration: LocalDotRunnerConfig
    let customLabels: [String]
    let previousCustomLabels: [String]
    private let readOnlyLabels: [String]
    private let remoteLabels: [String]
    private let originalLabels: [String]
    private let runnerID: UUID
    private let accountLogin: String

    init?(snapshot: RunnerSyncSnapshot, runner: RunnerEntity, account: GitHubAccountEntity, draft: [String]) {
        let selection = RunnerSyncAccount(account)
        guard account.isActive, snapshot.account == selection,
              let configuration = LocalDotRunnerConfig(runner),
              snapshot.configurations[runner.id] == configuration,
              case .found(let remote, _) = snapshot.results[runner.id],
              remote.id == configuration.agentId, remote.name == configuration.agentName,
              remote.labels.allSatisfy({ $0.type == "read-only" || $0.type == "custom" }) else { return nil }
        self.selection = selection
        self.configuration = configuration
        readOnlyLabels = remote.labels.filter { $0.type == "read-only" }.map(\.name)
        let builtIn = Self.names(readOnlyLabels)
        customLabels = draft.filter { !builtIn.contains($0.lowercased()) }
        previousCustomLabels = remote.labels.filter { $0.type == "custom" }.map(\.name)
        remoteLabels = remote.labelNames
        originalLabels = runner.labels
        runnerID = runner.id
        accountLogin = account.login
    }

    func matchesReviewedRemote(_ runner: GitHubRemoteRunnerDTO) -> Bool {
        runner.id == configuration.agentId && runner.name == configuration.agentName
            && Self.names(runner.labelNames) == Self.names(remoteLabels)
            && Self.names(runner.labels.filter { $0.type == "read-only" }.map(\.name)) == Self.names(readOnlyLabels)
    }

    func verifiesResult(_ names: [String]) -> Bool {
        Self.names(names) == Self.names(readOnlyLabels + customLabels)
    }

    func isCurrent(in context: ModelContext) throws -> Bool {
        try currentRunner(in: context) != nil
    }

    func apply(_ names: [String], in context: ModelContext) throws -> Bool {
        try Task.checkCancellation()
        guard verifiesResult(names), let runner = try currentRunner(in: context) else { return false }
        try context.transaction {
            runner.labels = names
            context.insert(AuditLogEntity(category: .configuration, title: "Runner Labels Updated on GitHub",
                summary: "Updated custom GitHub labels for \(runner.name)", actorAccountLogin: accountLogin,
                targetRunnerName: runner.name, previousValue: remoteLabels.joined(separator: ", "),
                newValue: names.joined(separator: ", ")))
        }
        return true
    }

    private func currentRunner(in context: ModelContext) throws -> RunnerEntity? {
        try Task.checkCancellation()
        let active = FetchDescriptor<GitHubAccountEntity>(predicate: #Predicate { $0.isActive })
        guard try context.fetch(active).first.map(RunnerSyncAccount.init) == selection else { return nil }
        let id = runnerID
        let descriptor = FetchDescriptor<RunnerEntity>(predicate: #Predicate { $0.id == id })
        guard let runner = try context.fetch(descriptor).first, LocalDotRunnerConfig(runner) == configuration,
              runner.labels == originalLabels else { return nil }
        return runner
    }

    private static func names(_ labels: [String]) -> Set<String> {
        Set(labels.map { $0.lowercased() })
    }
}
