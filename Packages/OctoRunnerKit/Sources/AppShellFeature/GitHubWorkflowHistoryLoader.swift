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
            for var run in page.items {
                if run.event?.hasPrefix("pull_request") == true, run.pullRequests?.isEmpty != false,
                   let sha = run.headSHA, responseRate?.remaining != 0 {
                    do {
                        var requests: [GitHubWorkflowPullRequestDTO] = []
                        var next: URL?
                        var visited = Set<URL>()
                        repeat {
                            guard visited.count < 20 else { throw WorkflowHistoryLoadError.tooManyPages }
                            let associations = try await client.pullRequests(repository: selection.repository, commitSHA: sha, token: token, page: next)
                            try Task.checkCancellation()
                            if let rate = associations.rateLimit { responseRate = rate }
                            requests.append(contentsOf: associations.items)
                            next = associations.nextPage
                            if let next {
                                guard responseRate?.remaining != 0 else {
                                    throw GitHubActionsError.httpStatus(429, rateLimit: responseRate)
                                }
                                guard visited.insert(next).inserted else { throw WorkflowHistoryLoadError.tooManyPages }
                            }
                        } while next != nil
                        run.pullRequests = requests
                    } catch let GitHubActionsError.httpStatus(status, rate) where
                        (status == 403 && rate?.remaining != 0 && rate?.retryAfterSeconds == nil) || status == 404 {
                        // Fine-grained Actions read does not imply Pull requests
                        // read. Keep the history useful, without inventing a PR.
                        run.pullRequests = nil
                    }
                }
                try Task.checkCancellation()
                if let attempt = run.runAttempt,
                   !(run.status == "completed" && completedAttempts.contains("\(run.id)/\(attempt)")) {
                    var jobs: [GitHubWorkflowJobDTO] = []
                    var next: URL?
                    var visited: Set<URL> = []
                    var pages = 0
                    var complete = true
                    var expectedTotal: Int?
                    repeat {
                        if responseRate?.remaining == 0 { complete = false; break }
                        guard pages < 20 else { throw WorkflowHistoryLoadError.tooManyPages }
                        let response = try await client.workflowJobs(repository: selection.repository, runID: run.id, attempt: attempt, token: token, page: next)
                        try Task.checkCancellation()
                        if let rate = response.rateLimit { responseRate = rate }
                        guard response.totalCount >= 0, expectedTotal == nil || expectedTotal == response.totalCount else {
                            throw WorkflowHistoryLoadError.unavailable
                        }
                        expectedTotal = response.totalCount
                        jobs.append(contentsOf: response.items)
                        next = response.nextPage
                        pages += 1
                        if let next, !visited.insert(next).inserted { throw WorkflowHistoryLoadError.tooManyPages }
                    } while next != nil
                    if complete {
                        guard jobs.count == expectedTotal, Set(jobs.map(\.id)).count == jobs.count else {
                            throw WorkflowHistoryLoadError.unavailable
                        }
                    }
                    results.append(WorkflowRunDetails(run: run, jobs: complete ? jobs : nil))
                } else { results.append(WorkflowRunDetails(run: run, jobs: nil)) }
            }
            try Task.checkCancellation()
            return WorkflowHistoryPage(runs: results, nextPage: page.nextPage, rateLimit: responseRate, observedAt: observedAt)
        } catch let error as GitHubActionsError {
            switch error {
            case .httpStatus(401, _): throw WorkflowHistoryLoadError.authenticationRequired
            case .httpStatus(404, _): throw WorkflowHistoryLoadError.resourceNotFound
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
