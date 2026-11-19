import CoreModels
import Foundation

public actor GitHubJobLogLoader {
    public static let maximumBytes = 1_048_576
    private let transport: any GitHubJobLogTransport

    public init(transport: any GitHubJobLogTransport = GitHubJobLogURLSessionTransport()) { self.transport = transport }

    public func load(repository: String, jobID: Int64, token: String) async throws -> GitHubJobLogResult {
        try Task.checkCancellation()
        guard let slug = GitHubRepositorySlug(input: repository), jobID > 0 else { throw GitHubActionsError.invalidRepository }
        guard !token.isEmpty, token.utf8.allSatisfy({ (33...126).contains($0) }) else { throw GitHubActionsError.invalidToken }
        let url = URL(string: "https://api.github.com/repos/\(slug.rawValue)/actions/jobs/\(jobID)/logs")!
        var apiRequest = request(url)
        apiRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        apiRequest.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        apiRequest.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        var response = try await transport.send(apiRequest, maximumBytes: Self.maximumBytes + 1)
        try Task.checkCancellation()
        let rateHeaders = response.headers.filter { $0.key.hasPrefix("x-ratelimit-") || $0.key == "retry-after" }
        let apiRate = rateHeaders.isEmpty ? nil : GitHubRateLimitSnapshot(headers: rateHeaders)
        guard response.statusCode == 200 || response.statusCode == 302 else {
            throw GitHubActionsError.httpStatus(response.statusCode, rateLimit: apiRate)
        }
        if response.statusCode == 302 {
            guard let location = response.headers["location"], let download = URLComponents(string: location),
                  download.scheme == "https", let host = download.host?.lowercased(), host.contains("."),
                  host != "localhost", !host.hasSuffix(".localhost"), !host.hasSuffix(".local"),
                  host.contains(where: { $0.isLetter }), !host.contains(":"),
                  download.user == nil, download.password == nil, download.fragment == nil,
                  download.port == nil || download.port == 443, let destination = download.url else {
                throw GitHubJobLogError.invalidRedirect(rateLimit: apiRate)
            }
            // A fresh request carries neither the API token nor ambient cookies.
            do { response = try await transport.send(request(destination), maximumBytes: Self.maximumBytes + 1) }
            catch is CancellationError { throw CancellationError() }
            catch { throw GitHubJobLogError.downloadFailed(statusCode: nil, rateLimit: apiRate) }
            try Task.checkCancellation()
        }
        guard response.statusCode == 200 else {
            throw GitHubJobLogError.downloadFailed(statusCode: response.statusCode, rateLimit: apiRate)
        }
        let contentType = response.headers["content-type"]?.lowercased() ?? ""
        guard !contentType.contains("zip"), !contentType.contains("html"), !contentType.contains("json") else {
            throw GitHubJobLogError.unsupportedContent(rateLimit: apiRate)
        }
        let truncated = response.data.count > Self.maximumBytes
        let data = Data(response.data.prefix(Self.maximumBytes))
        guard !data.contains(0), !data.starts(with: [0x50, 0x4b, 3, 4]) else { throw GitHubJobLogError.unsupportedContent(rateLimit: apiRate) }
        // A bounded stream may end inside a UTF-8 scalar (at most three trailing bytes).
        var text = String(data: data, encoding: .utf8)
        if truncated && text == nil {
            for count in 1...min(3, data.count) {
                let tail = Array(data.suffix(count))
                let lead = tail[0]
                let length = (0xc2...0xdf).contains(lead) ? 2 : (0xe0...0xef).contains(lead) ? 3 : (0xf0...0xf4).contains(lead) ? 4 : 0
                guard count < length, tail.dropFirst().allSatisfy({ (0x80...0xbf).contains($0) }) else { continue }
                if count > 1 {
                    guard !(lead == 0xe0 && tail[1] < 0xa0), !(lead == 0xed && tail[1] > 0x9f),
                          !(lead == 0xf0 && tail[1] < 0x90), !(lead == 0xf4 && tail[1] > 0x8f) else { continue }
                }
                if let decoded = String(data: data.dropLast(count), encoding: .utf8) {
                    text = decoded; break
                }
            }
        }
        guard let text else { throw GitHubJobLogError.unsupportedContent(rateLimit: apiRate) }
        return .init(snapshot: .init(text: text, observedAt: .now, isTruncated: truncated), rateLimit: apiRate)
    }

    private func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        request.httpMethod = "GET"; request.httpShouldHandleCookies = false
        return request
    }
}
