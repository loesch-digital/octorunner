import Foundation
import GitHubAPI
import Observation
import SyncKit

@MainActor
@Observable
final class RunnerAccessReview {
    struct LocalRegistration: Hashable {
        let id: Int64
        let name: String
    }

    struct Check {
        let runners: RunnerScopeInventory
        var groups: RunnerGroupInventory?

        var runnerCount: Int? {
            guard case .available(let runners, _, _) = runners else { return nil }
            return runners.count
        }

        func matchingRunnerCount(_ local: Set<LocalRegistration>) -> Int? {
            guard case .available(let runners, _, _) = runners else { return nil }
            return runners.count { local.contains(LocalRegistration(id: $0.id, name: $0.name)) }
        }
    }

    struct Snapshot {
        let account: RunnerSyncAccount
        let checks: [URL: Check]
        let checkedAt: Date
    }

    private let client: GitHubRunnerSyncActor
    @ObservationIgnored private var activeOperation: UUID?
    private(set) var snapshot: Snapshot?

    init(client: GitHubRunnerSyncActor = GitHubRunnerSyncActor()) {
        self.client = client
    }

    func refresh(scopes: Set<URL>, account: RunnerSyncAccount, token: String) async throws {
        try Task.checkCancellation()
        let operation = UUID()
        activeOperation = operation
        snapshot = nil
        var checks: [URL: Check] = [:]
        var retryAt: Date?
        for scope in scopes.sorted(by: { $0.absoluteString < $1.absoluteString }) {
            guard isCurrent(operation, account: account) else { throw CancellationError() }
            if let retryAt, retryAt > .now {
                checks[scope] = Check(runners: .rateLimited(retryAt: retryAt))
                continue
            }
            let runners = try await client.inventory(for: scope, token: token) {
                await self.isCurrent(operation, account: account)
            }
            guard isCurrent(operation, account: account) else { throw CancellationError() }
            var check = Check(runners: runners)
            retryAt = runners.retryDeadline
            if case .available = runners,
               let target = try? GitHubRunnerProvisioningClient.parseOwnerAndRepo(from: scope), target.repo == nil {
                if let retryAt, retryAt > .now {
                    check.groups = .rateLimited(retryAt: retryAt)
                } else {
                    let groups = try await client.groupInventory(for: scope, token: token) {
                        await self.isCurrent(operation, account: account)
                    }
                    check.groups = groups
                    retryAt = groups.retryDeadline
                }
            }
            checks[scope] = check
        }
        guard isCurrent(operation, account: account) else { throw CancellationError() }
        snapshot = Snapshot(account: account, checks: checks, checkedAt: .now)
    }

    private func isCurrent(_ operation: UUID, account: RunnerSyncAccount) -> Bool {
        !Task.isCancelled && activeOperation == operation && GitHubAccountStore.selectionRevision == account.selectionRevision
    }
}
