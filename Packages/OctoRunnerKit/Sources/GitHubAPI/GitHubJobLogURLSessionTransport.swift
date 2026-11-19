import Foundation

public actor GitHubJobLogURLSessionTransport: GitHubJobLogTransport {
    private let session: URLSession
    private let redirects = GitHubActionsRedirectDelegate()

    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    public func send(_ request: URLRequest, maximumBytes: Int) async throws -> GitHubActionsHTTPResponse {
        let (bytes, response) = try await session.bytes(for: request, delegate: redirects)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw GitHubActionsError.invalidResponse }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            if let key = key as? String, let value = value as? String { headers[key] = value }
        }
        var data = Data()
        if http.statusCode == 200 {
            for try await byte in bytes {
                try Task.checkCancellation()
                guard data.count < maximumBytes else { break }
                data.append(byte)
                if data.count == maximumBytes { break }
            }
        }
        try Task.checkCancellation()
        return .init(statusCode: http.statusCode, headers: headers, data: data)
    }
}
