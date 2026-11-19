import Foundation

/// Must stop consumption at maximumBytes, including for chunked responses.
public protocol GitHubJobLogTransport: Sendable {
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> GitHubActionsHTTPResponse
}
