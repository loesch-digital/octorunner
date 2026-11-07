import CoreModels
import Foundation
import SecurityKit

public actor GitHubRunnerSyncActor {
    private let discoveryActor: LocalRunnerDiscoveryActor
    private let keychain: KeychainVaultActor
    private let urlSession: URLSession

    public init(
        discoveryActor: LocalRunnerDiscoveryActor = LocalRunnerDiscoveryActor(),
        keychain: KeychainVaultActor = KeychainVaultActor(),
        urlSession: URLSession = .shared
    ) {
        self.discoveryActor = discoveryActor
        self.keychain = keychain
        self.urlSession = urlSession
    }

    public func discoverAndReconcileRunners(
        accountLogin: String?,
        additionalDirectories: [URL] = []
    ) async -> [DiscoveredLocalRunner] {
        let localRunners = await discoveryActor.discoverAllLocalRunners(additionalDirectories: additionalDirectories)
        guard !localRunners.isEmpty else { return [] }

        let token: String?
        if let accountLogin {
            token = try? await keychain.readSecret(account: accountLogin)
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
        guard let target = config.ownerAndRepo else { return nil }
        let endpointURL: URL
        if let repo = target.repo {
            endpointURL = URL(string: "https://api.github.com/repos/\(target.owner)/\(repo)/actions/runners/\(config.agentId)")!
        } else {
            endpointURL = URL(string: "https://api.github.com/orgs/\(target.owner)/actions/runners/\(config.agentId)")!
        }

        var request = URLRequest(url: endpointURL)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.timeoutInterval = 12

        let (data, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            return nil
        }
        return try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: data)
    }
}
