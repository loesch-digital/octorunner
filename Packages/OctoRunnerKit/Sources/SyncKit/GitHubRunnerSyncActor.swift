import Foundation
import GitHubAPI

public actor GitHubRunnerSyncActor {
    private let transport: any GitHubActionsTransport

    public init(transport: any GitHubActionsTransport = GitHubActionsURLSessionTransport()) {
        self.transport = transport
    }

    public init(urlSession: URLSession) {
        self.init(transport: GitHubActionsURLSessionTransport(session: urlSession))
    }

    public func lookupRunner(
        for config: LocalDotRunnerConfig,
        token: String,
        eTag: String? = nil,
        now: Date? = nil
    ) async throws -> RunnerLookupResult {
        try Task.checkCancellation()
        guard Self.validToken(token) else { return .unauthorized }
        guard config.agentId > 0, let path = Self.runnerPath(for: config.gitHubUrl),
              let response = try await get("\(path)/\(config.agentId)", token: token, eTag: eTag) else {
            return .unavailable
        }
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
            if let retryAt = Self.retryAt(for: response, observedAt: now ?? .now) { return .rateLimited(retryAt: retryAt) }
            return .forbidden
        case 404:
            return .notFound
        default:
            return .unavailable
        }
    }

    public func inventory(
        for scope: URL,
        token: String,
        isCurrent: @Sendable () async -> Bool = { true }
    ) async throws -> RunnerScopeInventory {
        try Task.checkCancellation()
        guard Self.validToken(token) else { return .unauthorized }
        guard let path = Self.runnerPath(for: scope) else { return .unavailable }
        let deadline = ContinuousClock.now.advanced(by: .seconds(30))
        let pageSize = 100
        var pageNumber = 1
        var expectedTotal: Int?
        var runners: [GitHubRemoteRunnerDTO] = []
        var seenIDs: Set<Int64> = []
        while ContinuousClock.now < deadline {
            guard await isCurrent() else { throw CancellationError() }
            guard let response = try await get("\(path)?per_page=\(pageSize)&page=\(pageNumber)", token: token) else {
                return .unavailable
            }
            guard await isCurrent() else { throw CancellationError() }
            try Task.checkCancellation()
            switch response.statusCode {
            case 401: return .unauthorized
            case 403, 429:
                if let retryAt = Self.retryAt(for: response, observedAt: .now) { return .rateLimited(retryAt: retryAt) }
                return .forbidden
            case 200: break
            default: return .unavailable
            }
            guard let page = try? JSONDecoder().decode(InventoryPage.self, from: response.data),
                  expectedTotal == nil || expectedTotal == page.totalCount,
                  page.totalCount >= runners.count,
                  page.runners.count == min(pageSize, page.totalCount - runners.count) else {
                return .unavailable
            }
            for runner in page.runners {
                guard runner.id > 0, seenIDs.insert(runner.id).inserted else { return .unavailable }
            }
            runners.append(contentsOf: page.runners)
            let retryAt = Self.retryAt(for: response, observedAt: .now)
            if runners.count == page.totalCount {
                // A multi-page listing can change between requests, even when its total stays fixed.
                return .available(runners, singlePage: pageNumber == 1 && response.headers["link"] == nil, retryAt: retryAt)
            }
            if let retryAt { return .rateLimited(retryAt: retryAt) }
            expectedTotal = page.totalCount
            pageNumber += 1
        }
        return .unavailable
    }

    private static func runnerPath(for url: URL) -> String? {
        guard let target = try? GitHubRunnerProvisioningClient.parseOwnerAndRepo(from: url) else { return nil }
        let scope = target.repo.map { "repos/\(target.owner)/\($0)" } ?? "orgs/\(target.owner)"
        return "\(scope)/actions/runners"
    }

    private static func validToken(_ token: String) -> Bool {
        !token.isEmpty && token.utf8.allSatisfy { (33...126).contains($0) }
    }

    private func get(_ path: String, token: String, eTag: String? = nil) async throws -> GitHubActionsHTTPResponse? {
        try Task.checkCancellation()
        guard let url = URL(string: "https://api.github.com/\(path)") else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 12)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(eTag, forHTTPHeaderField: "If-None-Match")
        do {
            let response = try await transport.send(request)
            try Task.checkCancellation()
            return response
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return nil
        }
    }

    private static func retryAt(for response: GitHubActionsHTTPResponse, observedAt: Date) -> Date? {
        let rate = GitHubRateLimitSnapshot(headers: response.headers, observedAt: observedAt)
        if let seconds = rate.retryAfterSeconds { return observedAt.addingTimeInterval(seconds) }
        if rate.remaining == 0 || response.statusCode == 429 {
            return rate.resetAt.flatMap { $0 > observedAt ? $0 : nil } ?? observedAt.addingTimeInterval(60)
        }
        if response.data.count <= 16 * 1024,
           let error = try? JSONDecoder().decode(RateLimitMessage.self, from: response.data),
           error.message.localizedCaseInsensitiveContains("secondary rate limit") {
            return observedAt.addingTimeInterval(60)
        }
        return nil
    }

    private struct RateLimitMessage: Decodable {
        let message: String
    }

    private struct InventoryPage: Decodable {
        let totalCount: Int
        let runners: [GitHubRemoteRunnerDTO]

        enum CodingKeys: String, CodingKey {
            case totalCount = "total_count"
            case runners
        }
    }
}
