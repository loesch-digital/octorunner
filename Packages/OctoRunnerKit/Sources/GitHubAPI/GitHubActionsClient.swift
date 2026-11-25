import CoreModels
import Foundation

/// Read-only Actions REST API. Credentials never appear in URLs, errors or storage.
public actor GitHubActionsClient {
    /// Last observed metadata across requests. Use a page/error's own snapshot
    /// when making decisions about that specific request or credential.
    public private(set) var rateLimit: GitHubRateLimitSnapshot?
    private let transport: any GitHubActionsTransport

    public init(transport: any GitHubActionsTransport = GitHubActionsURLSessionTransport()) {
        self.transport = transport
    }

    public func workflowRuns(repository: String, token: String, page: URL? = nil, runningOnly: Bool = false) async throws -> GitHubActionsPage<GitHubWorkflowRunDTO> {
        let path = try repositoryPath(repository) + "/actions/runs"
        let (data, next, rate) = try await load(path: path, page: page, token: token, runningOnly: runningOnly)
        let result = try Self.decoder().decode(GitHubWorkflowRunsResponse.self, from: data)
        return GitHubActionsPage(items: result.workflowRuns, nextPage: next, totalCount: result.totalCount, rateLimit: rate)
    }

    public func workflowJobs(repository: String, runID: Int64, attempt: Int, token: String, page: URL? = nil) async throws -> GitHubActionsPage<GitHubWorkflowJobDTO> {
        guard runID > 0, attempt > 0 else { throw GitHubActionsError.invalidRunAttempt }
        let path = try repositoryPath(repository) + "/actions/runs/\(runID)/attempts/\(attempt)/jobs"
        let (data, next, rate) = try await load(path: path, page: page, token: token)
        let result = try Self.decoder().decode(GitHubWorkflowJobsResponse.self, from: data)
        guard result.jobs.allSatisfy({ $0.runID == runID && ($0.runAttempt == nil || $0.runAttempt == attempt) && $0.id > 0 && $0.hasValidStepIdentities }) else { throw GitHubActionsError.invalidResponse }
        return GitHubActionsPage(items: result.jobs, nextPage: next, totalCount: result.totalCount, rateLimit: rate)
    }

    public func workflowRunAttempt(repository: String, runID: Int64, attempt: Int, token: String) async throws -> GitHubActionsPage<GitHubWorkflowRunDTO> {
        guard runID > 0, attempt > 0 else { throw GitHubActionsError.invalidRunAttempt }
        let path = try repositoryPath(repository) + "/actions/runs/\(runID)/attempts/\(attempt)"
        let (data, next, rate) = try await load(path: path, page: nil, token: token)
        let run = try Self.decoder().decode(GitHubWorkflowRunDTO.self, from: data)
        guard run.id == runID, run.runAttempt == attempt, next == nil else { throw GitHubActionsError.invalidResponse }
        return .init(items: [run], nextPage: nil, totalCount: 1, rateLimit: rate)
    }

    public func pullRequests(repository: String, commitSHA: String, token: String, page: URL? = nil) async throws -> GitHubActionsPage<GitHubWorkflowPullRequestDTO> {
        guard [40, 64].contains(commitSHA.utf8.count),
              commitSHA.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw GitHubActionsError.invalidResponse
        }
        let path = try repositoryPath(repository) + "/commits/\(commitSHA)/pulls"
        let (data, next, rate) = try await load(path: path, page: page, token: token)
        let items = try Self.decoder().decode([GitHubWorkflowPullRequestDTO].self, from: data)
        return GitHubActionsPage(items: items, nextPage: next, totalCount: items.count, rateLimit: rate)
    }

    private func load(path: String, page: URL?, token: String, runningOnly: Bool = false) async throws -> (Data, URL?, GitHubRateLimitSnapshot?) {
        try Task.checkCancellation()
        guard !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw GitHubActionsError.invalidToken }
        let status = runningOnly ? "&status=in_progress" : ""
        guard let initial = URL(string: "https://api.github.com\(path)?per_page=100&page=1\(status)") else { throw GitHubActionsError.invalidRepository }
        let url = page ?? initial
        try validate(url, path: path, runningOnly: runningOnly)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"
        request.httpShouldHandleCookies = false
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        let response = try await transport.send(request)
        try Task.checkCancellation()
        let hasRateHeaders = response.headers.keys.contains { $0.hasPrefix("x-ratelimit-") || $0 == "retry-after" }
        let responseRate = hasRateHeaders ? GitHubRateLimitSnapshot(headers: response.headers) : nil
        if let responseRate { rateLimit = responseRate }
        guard response.statusCode == 200 else { throw GitHubActionsError.httpStatus(response.statusCode, rateLimit: responseRate) }
        let next = try nextPage(from: response.headers["link"], path: path, runningOnly: runningOnly)
        return (response.data, next, responseRate)
    }

    private func repositoryPath(_ repository: String) throws -> String {
        guard GitHubRepositorySlug(slug: repository) != nil else { throw GitHubActionsError.invalidRepository }
        return "/repos/\(repository)"
    }

    private func validate(_ url: URL, path: String, runningOnly: Bool) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "https", components.host == "api.github.com",
              components.port == nil || components.port == 443,
              components.user == nil, components.password == nil, components.fragment == nil,
              components.percentEncodedPath == path else { throw GitHubActionsError.invalidPagination }
        let items = components.queryItems ?? []
        guard !items.isEmpty, items.contains(where: { $0.name == "status" }) == runningOnly,
              Set(items.map(\.name)).count == items.count,
              items.allSatisfy({ item in
                  if item.name == "status" { return item.value == "in_progress" }
                  guard let value = item.value, let number = Int(value) else { return false }
                  switch item.name {
                  case "page": return (1...100_000).contains(number)
                  case "per_page": return (1...100).contains(number)
                  default: return false
                  }
              }) else { throw GitHubActionsError.invalidPagination }
    }

    private func nextPage(from link: String?, path: String, runningOnly: Bool) throws -> URL? {
        guard let link else { return nil }
        for part in link.split(separator: ",") {
            let components = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard components.dropFirst().contains("rel=\"next\"") else { continue }
            guard let target = components.first, target.hasPrefix("<"), target.hasSuffix(">"),
                  var linked = URLComponents(string: String(target.dropFirst().dropLast())) else {
                throw GitHubActionsError.invalidPagination
            }
            if linked.percentEncodedPath != path {
                // GitHub may use /repositories/{id} for the same endpoint in
                // Link. Keep only its paging parameters, never its repository.
                let expected = path.split(separator: "/", maxSplits: 3)
                let received = linked.percentEncodedPath.dropFirst()
                    .split(separator: "/", maxSplits: 2, omittingEmptySubsequences: false)
                guard linked.percentEncodedPath.hasPrefix("/repositories/"),
                      expected.count == 4, received.count == 3, received[2] == expected[3],
                      received[1].utf8.allSatisfy({ (48...57).contains($0) }),
                      let repositoryID = Int64(received[1]), repositoryID > 0 else {
                    throw GitHubActionsError.invalidPagination
                }
                linked.percentEncodedPath = path
            }
            guard let url = linked.url else { throw GitHubActionsError.invalidPagination }
            try validate(url, path: path, runningOnly: runningOnly)
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
