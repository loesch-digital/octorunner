import CoreModels
import Foundation
import GitHubAPI
import SecurityKit

public actor GitHubRunnerSyncActor {
    private let discoveryActor: LocalRunnerDiscoveryActor
    private let keychain: KeychainVaultActor
    private let transport: any GitHubActionsTransport

    public init(
        discoveryActor: LocalRunnerDiscoveryActor = LocalRunnerDiscoveryActor(),
        keychain: KeychainVaultActor = KeychainVaultActor(),
        transport: any GitHubActionsTransport = GitHubActionsURLSessionTransport()
    ) {
        self.discoveryActor = discoveryActor
        self.keychain = keychain
        self.transport = transport
    }

    public init(discoveryActor: LocalRunnerDiscoveryActor = LocalRunnerDiscoveryActor(),
                keychain: KeychainVaultActor = KeychainVaultActor(), urlSession: URLSession) {
        self.init(discoveryActor: discoveryActor, keychain: keychain,
                  transport: GitHubActionsURLSessionTransport(session: urlSession))
    }

    public func discoverAndReconcileRunners(
        accountKey: String?,
        additionalDirectories: [URL] = []
    ) async -> [DiscoveredLocalRunner] {
        let localRunners = await discoveryActor.discoverAllLocalRunners(additionalDirectories: additionalDirectories)
        guard !localRunners.isEmpty else { return [] }

        let token: String?
        if let accountKey, !accountKey.isEmpty {
            token = try? await keychain.readSecret(account: accountKey)
        } else {
            token = nil
        }

        guard let token, !token.isEmpty else {
            return localRunners
        }

        // Structured concurrency (withTaskGroup) per swift-concurrency-pro
        return await withTaskGroup(of: DiscoveredLocalRunner.self) { group in
            for runner in localRunners {
                group.addTask {
                    var updated = runner
                    if let remote = try? await self.fetchRemoteRunner(for: runner.config, token: token) {
                        if !remote.labelNames.isEmpty {
                            updated.labels = remote.labelNames
                        }
                        if remote.busy {
                            updated.localStatus = .busy
                        } else if remote.status == "online" {
                            updated.localStatus = .idle
                        }
                    }
                    return updated
                }
            }

            var enriched: [DiscoveredLocalRunner] = []
            for await item in group {
                enriched.append(item)
            }
            return enriched.sorted { $0.config.agentName < $1.config.agentName }
        }
    }

    public func fetchRemoteRunner(
        for config: LocalDotRunnerConfig,
        token: String
    ) async throws -> GitHubRemoteRunnerDTO? {
        guard case .found(let runner, _) = try await lookupRunner(for: config, token: token) else { return nil }
        return runner
    }

    public func lookupRunner(
        for config: LocalDotRunnerConfig,
        token: String,
        eTag: String? = nil,
        now: Date? = nil
    ) async throws -> RunnerLookupResult {
        try Task.checkCancellation()
        guard !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }) else {
            return .unauthorized
        }
        guard config.agentId > 0, LocalDotRunnerConfig.isGitHubScope(config.gitHubUrl),
              let target = config.ownerAndRepo else { return .unavailable }
        let scope = target.repo.map { "repos/\(target.owner)/\($0)" } ?? "orgs/\(target.owner)"
        guard let url = URL(string: "https://api.github.com/\(scope)/actions/runners/\(config.agentId)") else {
            return .unavailable
        }

        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(eTag, forHTTPHeaderField: "If-None-Match")

        let response: GitHubActionsHTTPResponse
        do {
            response = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return .unavailable
        }
        try Task.checkCancellation()
        switch response.statusCode {
        case 200:
            guard let runner = try? JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: response.data),
                  runner.id == config.agentId else { return .unavailable }
            return .found(runner, eTag: response.headers["etag"])
        case 304:
            return eTag == nil ? .unavailable : .notModified
        case 401:
            return .unauthorized
        case 403, 429:
            let observedAt = now ?? .now
            let rate = GitHubRateLimitSnapshot(headers: response.headers, observedAt: observedAt)
            if let seconds = rate.retryAfterSeconds {
                return .rateLimited(retryAt: observedAt.addingTimeInterval(seconds))
            }
            if rate.remaining == 0 || response.statusCode == 429 {
                let validReset = rate.resetAt.flatMap { $0 > observedAt ? $0 : nil }
                return .rateLimited(retryAt: validReset ?? observedAt.addingTimeInterval(60))
            }
            return .forbidden
        case 404:
            return .notFound
        default:
            return .unavailable
        }
    }
}
