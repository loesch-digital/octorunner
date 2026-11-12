import Foundation

/// Read-only Actions REST API. Credentials never appear in URLs, errors or storage.
public actor GitHubActionsClient {
    public private(set) var rateLimit: GitHubRateLimitSnapshot?
    private let transport: any GitHubActionsTransport

    public init(transport: any GitHubActionsTransport = GitHubActionsURLSessionTransport()) {
        self.transport = transport
    }

    public func workflowRuns(repository: String, token: String, page: URL? = nil) async throws -> GitHubActionsPage<GitHubWorkflowRunDTO> {
        let path = try repositoryPath(repository) + "/actions/runs"
        let (data, next) = try await load(path: path, page: page, token: token)
        let result = try Self.decoder().decode(GitHubWorkflowRunsResponse.self, from: data)
        return GitHubActionsPage(items: result.workflowRuns, nextPage: next, totalCount: result.totalCount)
    }

    public func workflowJobs(repository: String, runID: Int64, attempt: Int, token: String, page: URL? = nil) async throws -> GitHubActionsPage<GitHubWorkflowJobDTO> {
        guard runID > 0, attempt > 0 else { throw GitHubActionsError.invalidRunAttempt }
        let path = try repositoryPath(repository) + "/actions/runs/\(runID)/attempts/\(attempt)/jobs"
        let (data, next) = try await load(path: path, page: page, token: token)
        let result = try Self.decoder().decode(GitHubWorkflowJobsResponse.self, from: data)
        guard result.jobs.allSatisfy({ $0.runID == runID }) else { throw GitHubActionsError.invalidResponse }
        return GitHubActionsPage(items: result.jobs, nextPage: next, totalCount: result.totalCount)
    }

    private func load(path: String, page: URL?, token: String) async throws -> (Data, URL?) {
        try Task.checkCancellation()
        guard !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw GitHubActionsError.invalidToken }
        guard let initial = URL(string: "https://api.github.com\(path)?per_page=100&page=1") else { throw GitHubActionsError.invalidRepository }
        let url = page ?? initial
        try validate(url, path: path)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        if response.headers.keys.contains(where: { $0.hasPrefix("x-ratelimit-") || $0 == "retry-after" }) {
            rateLimit = GitHubRateLimitSnapshot(headers: response.headers)
        }
        guard response.statusCode == 200 else { throw GitHubActionsError.httpStatus(response.statusCode) }
        let next = try nextPage(from: response.headers["link"], path: path)
        return (response.data, next)
    }

    private func repositoryPath(_ repository: String) throws -> String {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            throw GitHubActionsError.invalidRepository
        }
        return "/repos/\(repository)"
    }

    private func validate(_ url: URL, path: String) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "api.github.com",
              components.port == nil || components.port == 443,
              components.user == nil, components.password == nil, components.fragment == nil,
              components.percentEncodedPath == path else { throw GitHubActionsError.invalidPagination }
        let items = components.queryItems ?? []
        guard !items.isEmpty, Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ item in
                  guard let value = item.value, let number = Int(value) else { return false }
                  switch item.name {
                  case "page": return (1...100_000).contains(number)
                  case "per_page": return (1...100).contains(number)
                  default: return false
                  }
              }) else { throw GitHubActionsError.invalidPagination }
    }

    private func nextPage(from link: String?, path: String) throws -> URL? {
        guard let link else { return nil }
        for part in link.split(separator: ",") {
            let components = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard components.dropFirst().contains("rel=\"next\"") else { continue }
            guard let target = components.first, target.hasPrefix("<"), target.hasSuffix(">"),
                  let url = URL(string: String(target.dropFirst().dropLast())) else { throw GitHubActionsError.invalidPagination }
            try validate(url, path: path)
            return url
        }
        return nil
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            if let date = try? Date(value, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return date }
            return try Date(value, strategy: .iso8601)
        }
        return decoder
    }
}
