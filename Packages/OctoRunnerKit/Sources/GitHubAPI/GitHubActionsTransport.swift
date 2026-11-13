import Foundation

public protocol GitHubActionsTransport: Sendable {
    func send(_ request: URLRequest) async throws -> GitHubActionsHTTPResponse
}
