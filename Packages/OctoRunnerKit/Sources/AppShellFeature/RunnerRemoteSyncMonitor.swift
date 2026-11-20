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

    public init(scheduler: RunnerSyncScheduler) {
        self.scheduler = scheduler
    }

    public convenience init() {
        let auth = GitHubRunnerProvisioningClient()
        let sync = GitHubRunnerSyncActor()
        self.init(scheduler: RunnerSyncScheduler { configuration, account, eTag, _ in
            do {
                let token = try await auth.readToken(for: account.credentialKey)
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
        snapshot = nil
    }

    func refresh(in context: ModelContext) async {
        guard !Task.isCancelled else { return }
        do {
            guard let account = try selectedAccount(in: context) else {
                snapshot = nil
                await scheduler.clearAccount()
                return
            }
            if snapshot?.account != account { snapshot = nil }
            let configurations = try configurations(in: context)
            guard let refreshed = await scheduler.refresh(account: account, runners: configurations),
                  !Task.isCancelled else { return }
            guard try selectedAccount(in: context) == account else {
                if snapshot?.account == account { snapshot = nil }
                return
            }
            let current = try self.configurations(in: context)
            guard refreshed.configurations == current else { return }
            snapshot = refreshed
        } catch {
            guard !Task.isCancelled else { return }
            snapshot = nil
        }
    }

    private func selectedAccount(in context: ModelContext) throws -> RunnerSyncAccount? {
        let descriptor = FetchDescriptor<GitHubAccountEntity>(predicate: #Predicate { $0.isActive })
        return try context.fetch(descriptor).first.map {
            RunnerSyncAccount(id: $0.id, credentialKey: $0.keychainAccountKey, connectedAt: $0.connectedAt)
        }
    }

    private func configurations(in context: ModelContext) throws -> [UUID: LocalDotRunnerConfig] {
        var configurations: [UUID: LocalDotRunnerConfig] = [:]
        for runner in try context.fetch(FetchDescriptor<RunnerEntity>()) {
            guard let id = runner.githubRunnerId, id > 0,
                  let scope = URL(string: runner.scopeUrlString), LocalDotRunnerConfig.isGitHubScope(scope) else { continue }
            configurations[runner.id] = LocalDotRunnerConfig(agentId: id, agentName: runner.name, gitHubUrl: scope)
        }
        return configurations
    }
}
