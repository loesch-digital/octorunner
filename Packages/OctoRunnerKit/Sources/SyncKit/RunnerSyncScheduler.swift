import Foundation

public struct RunnerSyncAccount: Sendable, Equatable {
    public let id: UUID
    public let credentialKey: String
    public let connectedAt: Date

    public init(id: UUID, credentialKey: String, connectedAt: Date) {
        self.id = id
        self.credentialKey = credentialKey
        self.connectedAt = connectedAt
    }
}

public struct RunnerSyncSnapshot: Sendable {
    public let account: RunnerSyncAccount
    public let observedAt: Date
    public let configurations: [UUID: LocalDotRunnerConfig]
    public let results: [UUID: RunnerLookupResult]
}

public actor RunnerSyncScheduler {
    private typealias Observation = (configuration: LocalDotRunnerConfig, runner: GitHubRemoteRunnerDTO, eTag: String)
    private let lookup: @Sendable (LocalDotRunnerConfig, RunnerSyncAccount, String?, Date) async throws -> RunnerLookupResult
    private var currentAccount: RunnerSyncAccount?
    private var activeOperation: UUID?
    private var observations: [UUID: Observation] = [:]
    private var retryAt: Date?

    public init(
        lookup: @escaping @Sendable (LocalDotRunnerConfig, RunnerSyncAccount, String?, Date) async throws -> RunnerLookupResult
    ) {
        self.lookup = lookup
    }

    public func clearAccount() {
        currentAccount = nil
        activeOperation = nil
        observations = [:]
        retryAt = nil
    }

    public func refresh(
        account: RunnerSyncAccount,
        runners: [UUID: LocalDotRunnerConfig],
        now: Date = .now
    ) async -> RunnerSyncSnapshot? {
        guard !Task.isCancelled else { return nil }
        if currentAccount != account {
            clearAccount()
            currentAccount = account
        }
        guard activeOperation == nil else { return nil }
        let operation = UUID()
        activeOperation = operation
        defer {
            if activeOperation == operation { activeOperation = nil }
        }

        observations = observations.filter { runners[$0.key] == $0.value.configuration }
        var results: [UUID: RunnerLookupResult] = [:]
        for (id, configuration) in runners.sorted(by: { $0.key.uuidString < $1.key.uuidString }) {
            if let retryAt, now < retryAt {
                results[id] = .rateLimited(retryAt: retryAt)
                continue
            }
            let observation = observations[id]
            let result: RunnerLookupResult
            do {
                result = try await lookup(configuration, account, observation?.eTag, now)
            } catch is CancellationError {
                return nil
            } catch {
                result = .unavailable
            }
            guard !Task.isCancelled, activeOperation == operation else { return nil }
            switch result {
            case .found(let runner, let eTag):
                observations[id] = eTag.map { (configuration, runner, $0) }
                results[id] = result
            case .notModified:
                results[id] = observation.map { .found($0.runner, eTag: $0.eTag) } ?? .unavailable
            case .rateLimited(let date):
                retryAt = date
                results[id] = result
            case .notFound, .forbidden, .unauthorized:
                observations[id] = nil
                results[id] = result
            case .unavailable:
                results[id] = result
            }
        }
        return RunnerSyncSnapshot(account: account, observedAt: now, configurations: runners, results: results)
    }
}
