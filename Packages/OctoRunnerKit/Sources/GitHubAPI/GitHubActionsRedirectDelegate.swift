import Foundation

/// A moved repository must be selected again. Never forward its authorization.
public final class GitHubActionsRedirectDelegate: NSObject, URLSessionTaskDelegate {
    public func urlSession(_ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest) async -> URLRequest? {
        nil
    }
}
