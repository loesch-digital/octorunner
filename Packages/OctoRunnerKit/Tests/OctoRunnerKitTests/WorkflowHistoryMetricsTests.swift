import CoreModels
import Foundation
import Testing

@MainActor
struct WorkflowHistoryMetricsTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test("Empty or unresolved history never claims a perfect success rate or SLA")
    func unknownMetrics() {
        let empty = WorkflowHistoryMetrics(entries: [], now: now)
        #expect(empty.successRate == nil && empty.averageDurationSeconds == nil && empty.durationSLARate == nil)
        let unknown = entry(run: 1, conclusion: nil)
        let values = WorkflowHistoryMetrics(entries: [unknown], now: now)
        #expect(values.successRate == nil)
    }

    @Test("Measured durations remain useful when the run conclusion is unknown or neutral")
    func independentDurations() {
        let entries = [entry(run: 1, conclusion: nil, duration: 60), entry(run: 2, conclusion: "neutral", duration: 120)]
        let metrics = WorkflowHistoryMetrics(entries: entries, now: now, durationSLASeconds: 90)
        #expect(metrics.successRate == nil && metrics.resolvedRunCount == 0)
        #expect(metrics.durationSampleCount == 2 && metrics.averageDurationSeconds == 90)
        #expect(metrics.durationSLARate == 0.5)
    }

    @Test("Metrics count the latest workflow attempt once, excluding its matrix jobs")
    func attemptsAndMatrix() {
        let failed = entry(run: 1, attempt: 1, conclusion: "failure", duration: 600)
        let success = entry(run: 1, attempt: 2, conclusion: "success", duration: 60)
        let matrix = entry(run: 1, attempt: 2, conclusion: "failure", duration: 500, job: 99)
        let second = entry(run: 2, conclusion: "failure", duration: 120)
        let cancelled = entry(run: 3, conclusion: "cancelled", duration: nil)
        let skipped = entry(run: 4, conclusion: "skipped", duration: nil)
        let entries = [failed, success, matrix, second, cancelled, skipped]
        let metrics = WorkflowHistoryMetrics(entries: entries, now: now, durationSLASeconds: 90)
        #expect(metrics.successRate == 0.5)
        #expect(metrics.averageDurationSeconds == 90)
        #expect(metrics.durationSLARate == 0.5)
        #expect(metrics.completedToday == 4)
        #expect(metrics.resolvedRunCount == 2 && metrics.durationSampleCount == 2)
        // A later successful attempt prevents an obsolete failure from appearing.
        #expect(WorkflowHistoryFilter(status: .failed).apply(to: entries).map(\.githubRunID) == [2])
    }

    @Test("Account and repository identities remain independent; unknown attempts never supersede known ones")
    func identities() {
        let entries = [entry(run: 1, conclusion: "success"), entry(run: 1, attempt: nil, conclusion: "failure"), entry(run: 1, conclusion: "failure", repository: "example/other"), entry(run: 1, conclusion: "success", account: 8)]
        #expect(WorkflowHistoryFilter().apply(to: entries).count == 3)
        #expect(WorkflowHistoryFilter(accountID: 7, repository: "EXAMPLE/REPO").apply(to: entries).count == 1)
    }

    @Test("Queue and runner filters use the current attempt's assigned jobs and search workflow metadata")
    func filters() {
        var entries = [entry(run: 1, attempt: 1, conclusion: "failure", job: 100, runner: 31), entry(run: 1, attempt: 2, conclusion: "success"), entry(run: 1, attempt: 2, conclusion: "success", job: 101, runner: 32)]
        #expect(WorkflowHistoryFilter(runnerID: 31).apply(to: entries).isEmpty)
        #expect(WorkflowHistoryFilter(runnerID: 32, search: "fixture-sha").apply(to: entries).count == 1)
        let queued = entry(run: 2, conclusion: nil, status: "queued")
        let running = entry(run: 3, conclusion: nil, status: "in_progress")
        entries += [queued, running]
        let metrics = WorkflowHistoryMetrics(entries: entries, now: now)
        #expect(metrics.runningCount == 1 && metrics.queuedCount == 1)
        #expect(WorkflowHistoryFilter(status: .queued).apply(to: entries).map(\.githubRunID) == [2])
        #expect(WorkflowHistoryFilter(search: "missing").apply(to: entries).isEmpty)
    }

    @Test("Status filters distinguish successful, running and cancelled runs from unknown conclusions")
    func statusFilters() {
        let entries = [entry(run: 1, conclusion: "success"), entry(run: 2, conclusion: "cancelled"), entry(run: 3, conclusion: nil, status: "in_progress"), entry(run: 4, conclusion: nil)]
        #expect(WorkflowHistoryFilter(status: .succeeded).apply(to: entries).map(\.githubRunID) == [1])
        #expect(WorkflowHistoryFilter(status: .cancelled).apply(to: entries).map(\.githubRunID) == [2])
        #expect(WorkflowHistoryFilter(status: .running).apply(to: entries).map(\.githubRunID) == [3])
    }

    private func entry(run: Int64, attempt: Int? = 1, conclusion: String?, duration: Double? = nil,
        job: Int64? = nil, repository: String = "example/repo", account: Int64 = 7,
        status: String = "completed", runner: Int64? = nil) -> WorkflowHistoryEntry {
        let entity = JobRunEntity(githubRunId: run, workflowName: "CI", repositoryFullName: repository, branchName: "main", commitSha: "fixture-sha", statusRaw: status)
        entity.sourceRaw = "github"
        entity.observedAt = now
        entity.accountGitHubUserID = account
        entity.runAttempt = attempt
        entity.conclusion = conclusion
        entity.githubJobId = job
        entity.recordKindRaw = job == nil ? "workflow" : "job"
        entity.githubRunnerIDSnapshot = runner
        entity.completedAt = status == "completed" ? now.addingTimeInterval(-10) : nil
        entity.actualStartedAt = duration.map { now.addingTimeInterval(-10 - $0) }
        return WorkflowHistoryEntry(entity)
    }
}
