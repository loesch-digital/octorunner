import Foundation

public actor GitHubActionsURLSessionTransport: GitHubActionsTransport {
    private let session: URLSession
    private let redirectDelegate = GitHubActionsRedirectDelegate()

    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    public func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse {
        let (data, response) = try await session.data(for: request, delegate: redirectDelegate)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw GitHubActionsError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        return GitHubActionsHTTPResponse(statusCode: http.statusCode, headers: headers, data: data)
    }
}
