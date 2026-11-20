import Foundation
import GitHubAPI
import SyncKit

struct RunnerMigrationGitHubChecks: Sendable {
    var transport: any GitHubActionsTransport = GitHubActionsURLSessionTransport()

    func runner(for config: LocalDotRunnerConfig, token: String) async throws -> GitHubRemoteRunnerDTO? {
        guard let path = Self.runnerPath(for: config) else { return nil }
        return try await get(path, token: token)
    }

    func previousRunnerIsAbsent(for config: LocalDotRunnerConfig, previousID: Int64? = nil, token: String) async throws -> Bool {
        guard let path = Self.runnerPath(for: config, runnerID: previousID) else { return false }
        return try await response(path, token: token)?.statusCode == 404
    }

    func group(for config: LocalDotRunnerConfig, runnerID: Int64, token: String) async throws -> RunnerMigrationGroup? {
        guard config.inferredScopeType == .organization, runnerID > 0,
              let scope = Self.scopePath(for: config), let groupID = config.poolId, groupID > 0 else {
            return nil
        }
        let path = "/\(scope)/actions/runner-groups/\(groupID)"
        guard let group: Group = try await get(path, token: token), group.id == groupID else { return nil }
        let pageSize = 100
        var pageNumber = 1
        var visitedIDs: Set<Int64> = []
        while let page: Members = try await get(
            "\(path)/runners?per_page=\(pageSize)&page=\(pageNumber)", token: token
        ) {
            let ids = Set(page.runners.map(\.id))
            guard (1...pageSize).contains(page.runners.count), ids.count == page.runners.count,
                  ids.isDisjoint(with: visitedIDs), page.totalCount >= visitedIDs.count + ids.count else { return nil }
            if ids.contains(runnerID) { return RunnerMigrationGroup(id: group.id, name: group.name) }
            visitedIDs.formUnion(ids)
            guard page.runners.count == pageSize, visitedIDs.count < page.totalCount else { return nil }
            pageNumber += 1
        }
        return nil
    }

    private static func scopePath(for config: LocalDotRunnerConfig) -> String? {
        guard LocalDotRunnerConfig.isGitHubScope(config.gitHubUrl), let target = config.ownerAndRepo else {
            return nil
        }
        if let repository = target.repo { return "repos/\(target.owner)/\(repository)" }
        return "orgs/\(target.owner)"
    }

    private static func runnerPath(for config: LocalDotRunnerConfig, runnerID: Int64? = nil) -> String? {
        let id = runnerID ?? config.agentId
        guard id > 0, let scope = scopePath(for: config) else { return nil }
        return "/\(scope)/actions/runners/\(id)"
    }

    private func get<Value: Decodable>(_ path: String, token: String) async throws -> Value? {
        guard let reply = try await response(path, token: token), reply.statusCode == 200 else { return nil }
        return try JSONDecoder().decode(Value.self, from: reply.data)
    }

    private func response(_ path: String, token: String) async throws -> GitHubActionsHTTPResponse? {
        try Task.checkCancellation()
        guard !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }),
              let url = URL(string: "https://api.github.com\(path)") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        return response
    }

    private struct Group: Decodable {
        let id: Int
        let name: String
    }

    private struct Members: Decodable {
        struct Runner: Decodable {
            let id: Int64
        }

        let totalCount: Int
        let runners: [Runner]

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case runners
        }
    }
}
