import CoreModels
import Foundation
import GitHubAPI
import Observation
import SwiftData
import SyncKit

/// Collects GitHub observations while the app runs, independently of window visibility.
@MainActor
@Observable
public final class RunnerRemoteSyncMonitor {
    public private(set) var snapshot: RunnerSyncSnapshot?
    @ObservationIgnored private let scheduler: RunnerSyncScheduler
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var isUpdatingLabels = false

    public init(scheduler: RunnerSyncScheduler) {
        self.scheduler = scheduler
    }

    public convenience init() {
        let auth = GitHubRunnerProvisioningClient()
        let sync = GitHubRunnerSyncActor()
        self.init(scheduler: RunnerSyncScheduler(inventory: { scope, account, isCurrent in
            do {
                let token = try await auth.readToken(for: account.credentialKey)
                return try await sync.inventory(for: scope, token: token, isCurrent: isCurrent)
            } catch GitHubProvisioningError.missingAuthToken {
                return .unauthorized
            }
        }) { configuration, account, eTag, _ in
            do {
                let token = try await auth.readToken(for: account.credentialKey)
                guard await GitHubAccountStore.selectionRevision == account.selectionRevision else {
                    throw CancellationError()
                }
                return try await sync.lookupRunner(for: configuration, token: token, eTag: eTag)
            } catch GitHubProvisioningError.missingAuthToken {
                return .unauthorized
            }
        })
    }

    public func start(container: ModelContainer) {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh(in: container.mainContext)
                guard self != nil else { return }
                do { try await Task.sleep(for: .seconds(60)) }
                catch { return }
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
        generation = UUID()
        snapshot = nil
    }

    func beginLabelUpdate() async -> Bool {
        guard !isUpdatingLabels, !Task.isCancelled else { return false }
        isUpdatingLabels = true
        generation = UUID()
        snapshot = nil
        await scheduler.clearAccount()
        return true
    }

    func endLabelUpdate() {
        isUpdatingLabels = false
    }

    func refresh(in context: ModelContext) async {
        guard !Task.isCancelled, !isUpdatingLabels else { return }
        let operation = generation
        do {
            guard let account = try selectedAccount(in: context) else {
                snapshot = nil
                await scheduler.clearAccount()
                return
            }
            if snapshot?.account != account { snapshot = nil }
            let configurations = try configurations(in: context)
            let refreshed = await scheduler.refresh(account: account, runners: configurations) {
                self.generation == operation && self.isCurrent(account, in: context)
            }
            guard let refreshed, !Task.isCancelled, generation == operation else { return }
            guard try selectedAccount(in: context) == account else {
                if snapshot?.account == account { snapshot = nil }
                return
            }
            let current = try self.configurations(in: context)
            guard refreshed.configurations == current else { return }
            snapshot = refreshed
        } catch {
            guard !Task.isCancelled, generation == operation else { return }
            snapshot = nil
        }
    }

    private func isCurrent(_ account: RunnerSyncAccount, in context: ModelContext) -> Bool {
        (try? selectedAccount(in: context)) == account
    }

    private func selectedAccount(in context: ModelContext) throws -> RunnerSyncAccount? {
        let descriptor = FetchDescriptor<GitHubAccountEntity>(predicate: #Predicate { $0.isActive })
        return try context.fetch(descriptor).first.map(RunnerSyncAccount.init)
    }

    private func configurations(in context: ModelContext) throws -> [UUID: LocalDotRunnerConfig] {
        var configurations: [UUID: LocalDotRunnerConfig] = [:]
        for runner in try context.fetch(FetchDescriptor<RunnerEntity>()) {
            configurations[runner.id] = LocalDotRunnerConfig(runner)
        }
        return configurations
    }
}

extension RunnerSyncAccount {
    @MainActor
    init(_ account: GitHubAccountEntity) {
        self.init(id: account.id, credentialKey: account.keychainAccountKey, connectedAt: account.connectedAt,
                  selectionRevision: GitHubAccountStore.selectionRevision)
    }
}

extension LocalDotRunnerConfig {
    @MainActor
    init?(_ runner: RunnerEntity) {
        guard let id = runner.githubRunnerId, id > 0,
              let scope = URL(string: runner.scopeUrlString), Self.isGitHubScope(scope) else { return nil }
        self.init(agentId: id, agentName: runner.name, gitHubUrl: scope)
    }
}
