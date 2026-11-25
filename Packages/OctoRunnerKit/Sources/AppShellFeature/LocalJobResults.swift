import CoreModels
import Foundation

/// Job outcomes never change runner availability. Only exact, unambiguous local
/// identities within the active account can contribute to this presentation.
public struct LocalJobResults: Sendable {
    public let latestByRunner: [UUID: WorkflowHistoryEntry]
    public let unreviewedFailures: [WorkflowHistoryEntry]

    private let runningJobs: [UUID: [WorkflowHistoryEntry]]
    private let runningWorkflowByAttempt: [String: WorkflowHistoryEntry]

    public init() {
        self.init(latestByRunner: [:], unreviewedFailures: [], runningJobs: [:], runningWorkflowByAttempt: [:])
    }

    func runningWorkflowCount(at now: Date, maxAge: TimeInterval = 90, repositories: Set<String>? = nil) -> Int {
        runningWorkflowByAttempt.values.count { entry in
            entry.isFresh(at: now, maxAge: maxAge) && (repositories?.contains(entry.repository) ?? true)
        }
    }

    func runningJob(for runnerID: UUID, at now: Date, maxAge: TimeInterval = 90) -> WorkflowHistoryEntry? {
        let jobs = (runningJobs[runnerID] ?? []).filter { job in
            job.isFresh(at: now, maxAge: maxAge) && runningWorkflowByAttempt[Self.attemptKey(job)]?.isFresh(at: now, maxAge: maxAge) == true
        }
        return jobs.count == 1 ? jobs.first : nil
    }

    func workflow(for job: WorkflowHistoryEntry) -> WorkflowHistoryEntry? {
        runningWorkflowByAttempt[Self.attemptKey(job)]
    }

    private static func attemptKey(_ entry: WorkflowHistoryEntry) -> String {
        "\(entry.repository.lowercased())|\(entry.githubRunID)|\(entry.attempt ?? 0)"
    }

    @MainActor
    public init(entries: [WorkflowHistoryEntry], runners: [RunnerEntity], accountID: Int64?,
                reviewed: Set<String>, now: Date = .now) {
        guard let accountID, accountID > 0 else {
            self.init()
            return
        }
        let entries = entries.filter { $0.accountID == accountID }
        let running = WorkflowHistoryFilter(status: .running).apply(to: entries)
        let workflowsByAttempt = Dictionary(uniqueKeysWithValues: running.map { (Self.attemptKey($0), $0) })
        var assignedJobs: [UUID: [WorkflowHistoryEntry]] = [:]
        let attempts = WorkflowHistoryFilter.latestAttempts(in: entries)
        var runnersByID: [Int64: [RunnerEntity]] = [:]
        for runner in runners {
            if let id = runner.githubRunnerId, id > 0 {
                runnersByID[id, default: []].append(runner)
            }
        }
        for entry in entries where entry.recordKind == "job" && entry.status == "in_progress" {
            guard (entry.githubJobID ?? 0) > 0, entry.githubRunID > 0, (entry.attempt ?? 0) > 0,
                  workflowsByAttempt[Self.attemptKey(entry)] != nil else { continue }
            let assigned = (runnersByID[entry.runnerID ?? 0] ?? []).filter { entry.matchesRunner($0) }
            guard assigned.count == 1, let runner = assigned.first else { continue }
            assignedJobs[runner.id, default: []].append(entry)
        }
        let completed = Self.completedResults(entries: entries, runnersByID: runnersByID, attempts: attempts,
            reviewed: reviewed, now: now)
        self.init(latestByRunner: completed.latest, unreviewedFailures: completed.failures,
            runningJobs: assignedJobs, runningWorkflowByAttempt: workflowsByAttempt)
    }

    private init(latestByRunner: [UUID: WorkflowHistoryEntry], unreviewedFailures: [WorkflowHistoryEntry],
                 runningJobs: [UUID: [WorkflowHistoryEntry]], runningWorkflowByAttempt: [String: WorkflowHistoryEntry]) {
        self.latestByRunner = latestByRunner
        self.unreviewedFailures = unreviewedFailures
        self.runningJobs = runningJobs
        self.runningWorkflowByAttempt = runningWorkflowByAttempt
    }

    @MainActor
    private static func completedResults(entries: [WorkflowHistoryEntry], runnersByID: [Int64: [RunnerEntity]],
                                         attempts: [String: Int], reviewed: Set<String>, now: Date)
        -> (latest: [UUID: WorkflowHistoryEntry], failures: [WorkflowHistoryEntry]) {
        var latest: [UUID: WorkflowHistoryEntry] = [:]
        var failures: [WorkflowHistoryEntry] = []
        var included: Set<String> = []
        for entry in entries.sorted(by: Self.newerFirst) {
            guard entry.recordKind == "job", entry.status == "completed",
                  (entry.githubJobID ?? 0) > 0, entry.githubRunID > 0,
                  let attempt = entry.attempt, attempt > 0,
                  let completed = entry.completedAt, completed <= now,
                  let observed = entry.observedAt, completed <= observed.addingTimeInterval(5),
                  observed <= now.addingTimeInterval(5) else { continue }
            let matches = (runnersByID[entry.runnerID ?? 0] ?? []).filter { entry.matchesRunner($0) }
            guard matches.count == 1, let runner = matches.first else { continue }
            let key = Self.reviewKey(entry)
            guard included.insert(key).inserted else { continue }
            if latest[runner.id] == nil { latest[runner.id] = entry }
            if Self.isFailure(entry), !reviewed.contains(key),
               attempts[entry.runKey] == attempt { failures.append(entry) }
        }
        return (latest, failures)
    }

    public static func reviewKey(_ entry: WorkflowHistoryEntry) -> String {
        "\(entry.accountID ?? 0)|\(entry.repository.lowercased())|\(entry.githubRunID)|\(entry.attempt ?? 0)|\(entry.githubJobID ?? 0)"
    }

    public static func isFailure(_ entry: WorkflowHistoryEntry) -> Bool {
        entry.status == "completed" && ["failure", "timed_out", "startup_failure", "action_required", "stale"].contains(entry.conclusion ?? "")
    }

    private static func newerFirst(_ left: WorkflowHistoryEntry, _ right: WorkflowHistoryEntry) -> Bool {
        if left.completedAt != right.completedAt { return (left.completedAt ?? .distantPast) > (right.completedAt ?? .distantPast) }
        if left.githubJobID != right.githubJobID { return (left.githubJobID ?? 0) > (right.githubJobID ?? 0) }
        return left.id.uuidString < right.id.uuidString
    }
}
