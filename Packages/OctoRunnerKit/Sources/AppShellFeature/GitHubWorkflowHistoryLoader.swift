import Foundation
import GitHubAPI
import SecurityKit

/// Small pages bound API traffic. Completed job details are immutable cache data;
/// running and queued attempts are fetched again on the next explicit refresh.
public actor GitHubWorkflowHistoryLoader: WorkflowHistoryLoading {
    private let client: GitHubActionsClient
    private let secrets: any SecretReading

    public init(client: GitHubActionsClient = GitHubActionsClient(), secrets: any SecretReading = KeychainVaultActor()) {
        self.client = client
        self.secrets = secrets
    }

    public func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage {
        try Task.checkCancellation()
        guard selection.accountID > 0, !selection.keychainAccountKey.isEmpty else { throw WorkflowHistoryLoadError.authenticationRequired }
        guard let token = try await secrets.readSecret(account: selection.keychainAccountKey, category: "github-oauth"), !token.isEmpty else {
            throw WorkflowHistoryLoadError.authenticationRequired
        }
        try Task.checkCancellation()
        do {
            let initial = URL(string: "https://api.github.com/repos/\(selection.repository)/actions/runs?per_page=10&page=1")
            let page = try await client.workflowRuns(repository: selection.repository, token: token, page: nextPage ?? initial)
            let observedAt = Date.now
            var responseRate = page.rateLimit
            var results: [WorkflowRunDetails] = []
            for run in page.items {
                try Task.checkCancellation()
                if let attempt = run.runAttempt,
                   !(run.status == "completed" && completedAttempts.contains("\(run.id)/\(attempt)")) {
                    var jobs: [GitHubWorkflowJobDTO] = []
                    var next: URL?
                    var visited: Set<URL> = []
                    var pages = 0
                    var complete = true
                    repeat {
                        if responseRate?.remaining == 0 { complete = false; break }
                        guard pages < 20 else { throw WorkflowHistoryLoadError.tooManyPages }
                        let response = try await client.workflowJobs(repository: selection.repository, runID: run.id, attempt: attempt, token: token, page: next)
                        try Task.checkCancellation()
                        if let rate = response.rateLimit { responseRate = rate }
                        jobs.append(contentsOf: response.items)
                        next = response.nextPage
                        pages += 1
                        if let next, !visited.insert(next).inserted { throw WorkflowHistoryLoadError.tooManyPages }
                    } while next != nil
                    results.append(WorkflowRunDetails(run: run, jobs: complete ? jobs : nil))
                } else { results.append(WorkflowRunDetails(run: run, jobs: nil)) }
            }
            try Task.checkCancellation()
            return WorkflowHistoryPage(runs: results, nextPage: page.nextPage, rateLimit: responseRate, observedAt: observedAt)
        } catch let error as GitHubActionsError {
            switch error {
            case .httpStatus(401, _): throw WorkflowHistoryLoadError.authenticationRequired
            case .httpStatus(let status, let rate) where status == 403 || status == 429:
                if rate?.remaining == 0 || rate?.retryAfterSeconds != nil || status == 429 {
                    let retry = rate?.retryAfterSeconds.map { Date.now.addingTimeInterval(TimeInterval($0)) }
                    let reset = rate?.remaining == 0 ? rate?.resetAt : nil
                    throw WorkflowHistoryLoadError.rateLimited(until: [retry, reset].compactMap { $0 }.max())
                }
                throw WorkflowHistoryLoadError.permissionDenied
            default: throw WorkflowHistoryLoadError.unavailable
            }
        }
    }
}
