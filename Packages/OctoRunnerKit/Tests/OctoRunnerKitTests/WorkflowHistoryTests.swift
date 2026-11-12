import AppShellFeature
import CoreModels
import Foundation
@testable import GitHubAPI
import SwiftData
import Testing

@MainActor
struct WorkflowHistoryTests {
    // SwiftData can retain cached relationship backing data beyond a test scope.
    private static var containers: [ModelContainer] = []

    @Test("A real v0.4 SQLite store retains accounts, jobs, runners and audit entries during migration")
    func legacyMigration() throws {
        let fixture = try #require(Bundle.module.url(forResource: "v0_4", withExtension: "store", subdirectory: "Fixtures"))
        let directory = FileManager.default.temporaryDirectory.appending(path: "octorunner-history-migration-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "history.store")
        try FileManager.default.copyItem(at: fixture, to: url)
        let schema = OctoRunnerPersistence.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        Self.containers.append(container)
        let context = container.mainContext
        let job = try #require(context.fetch(FetchDescriptor<JobRunEntity>()).first)
        #expect(job.id == UUID(uuidString: "00000000-0000-0000-0000-000000000042"))
        #expect(job.githubRunId == 42 && job.workflowName == "Legacy CI")
        #expect(job.startedAt == Date(timeIntervalSince1970: 1_700_000_000))
        #expect(job.durationSeconds == 42)
        #expect(job.runner?.name == "fixture-runner")
        #expect(job.runner?.jobRuns.count == 1)
        #expect(job.recordKindRaw == "workflow" && job.sourceRaw == "legacy")
        #expect(job.runAttempt == nil && job.githubJobId == nil && job.conclusion == nil)
        #expect(try context.fetch(FetchDescriptor<GitHubAccountEntity>()).map(\.login) == ["fixture-account"])
        #expect(try context.fetch(FetchDescriptor<AuditLogEntity>()).map(\.title) == ["Fixture audit"])
        #expect(try context.fetchCount(FetchDescriptor<RunnerEntity>()) == 1)
        _ = try WorkflowHistoryStore.upsert(run: workflow(attempt: 1), jobs: [self.job(id: 100)], repository: "example/repo", accountID: 7, in: context)
        try context.save()
        let freshContext = ModelContext(container)
        #expect(try freshContext.fetchCount(FetchDescriptor<JobRunEntity>()) == 3)
        #expect(try freshContext.fetch(FetchDescriptor<JobRunEntity>()).filter { $0.sourceRaw == "github" }.allSatisfy { $0.runAttempt == 1 && $0.accountGitHubUserID == 7 })
    }

    @Test("History upserts preserve identity per account, repository, attempt and job")
    func stableUpserts() throws {
        let context = try makeContext()
        let run = try workflow(attempt: 1)
        let first = try WorkflowHistoryStore.upsert(run: run, jobs: [job(id: 100), job(id: 101)], repository: "example/repo", accountID: 7, in: context)
        let again = try WorkflowHistoryStore.upsert(run: run, jobs: [job(id: 100)], repository: "EXAMPLE/REPO", accountID: 7, in: context)
        #expect(first.id == again.id)
        #expect(try context.fetchCount(FetchDescriptor<JobRunEntity>()) == 3)
        _ = try WorkflowHistoryStore.upsert(run: workflow(attempt: 2), jobs: [job(id: 102)], repository: "example/repo", accountID: 7, in: context)
        _ = try WorkflowHistoryStore.upsert(run: run, jobs: [], repository: "example/repo", accountID: 8, in: context)
        _ = try WorkflowHistoryStore.upsert(run: run, jobs: [], repository: "example/other", accountID: 7, in: context)
        #expect(try context.fetchCount(FetchDescriptor<JobRunEntity>()) == 7)
        #expect(first.sourceRaw == "github" && first.runAttempt == 1)
        #expect(first.runner == nil) // Matrix jobs can belong to different runners.
    }

    @Test("A known attempt supersedes an unknown snapshot in the visible history without guessing an attempt")
    func unknownToKnownAttempt() throws {
        let context = try makeContext()
        _ = try WorkflowHistoryStore.upsert(run: workflow(attempt: nil), jobs: [], repository: "example/repo", accountID: 7, in: context)
        _ = try WorkflowHistoryStore.upsert(run: workflow(attempt: 1), jobs: [], repository: "example/repo", accountID: 7, in: context)
        let records = try context.fetch(FetchDescriptor<JobRunEntity>())
        #expect(records.count == 2)
        let entries = records.map(WorkflowHistoryEntry.init)
        #expect(WorkflowHistoryFilter(accountID: 7).apply(to: entries).map(\.attempt) == [1])
        #expect(WorkflowHistoryMetrics(entries: entries).queuedCount == 1)
    }

    @Test("Unknown times remain unknown and running jobs never gain a fabricated duration")
    func unknownTimes() throws {
        let context = try makeContext()
        let entity = try WorkflowHistoryStore.upsert(run: workflow(attempt: nil), jobs: [], repository: "example/repo", accountID: 7, in: context)
        #expect(entity.runAttempt == nil && entity.actualStartedAt == nil && entity.completedAt == nil)
        #expect(entity.measuredDurationSeconds == nil)
        #expect(entity.conclusion == nil)
    }

    @Test("Completed run duration requires all job pages and never uses updated_at as completion")
    func measuredCompletion() throws {
        let context = try makeContext()
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(GitHubWorkflowRunDTO.self, from: Data(#"{"id":42,"status":"completed","conclusion":"success","run_attempt":1,"run_started_at":"2026-11-12T10:00:00Z","updated_at":"2026-11-12T12:00:00Z"}"#.utf8))
        let completedJob = try decoder.decode(GitHubWorkflowJobDTO.self, from: Data(#"{"id":100,"run_id":42,"name":"Build","status":"completed","conclusion":"success","started_at":"2026-11-12T10:00:05Z","completed_at":"2026-11-12T10:01:00Z","runner_id":31,"runner_name":"local-runner"}"#.utf8))
        let entity = try WorkflowHistoryStore.upsert(run: run, jobs: [completedJob], repository: "example/repo", accountID: 7, in: context)
        #expect(entity.completedAt == nil && entity.measuredDurationSeconds == nil)
        _ = try WorkflowHistoryStore.upsert(run: run, jobs: [completedJob], repository: "example/repo", accountID: 7, jobsComplete: true, in: context)
        #expect(entity.measuredDurationSeconds == 60)
        let job = try #require(context.fetch(FetchDescriptor<JobRunEntity>()).first { $0.githubJobId == 100 })
        #expect(job.measuredDurationSeconds == 55)
        #expect(job.runnerNameSnapshot == "local-runner" && job.githubRunnerIDSnapshot == 31)
        let laterJob = try decoder.decode(GitHubWorkflowJobDTO.self, from: Data(#"{"id":101,"run_id":42,"name":"Tests","status":"completed","completed_at":"2026-11-12T10:02:00Z"}"#.utf8))
        _ = try WorkflowHistoryStore.upsert(run: run, jobs: [completedJob, laterJob], repository: "example/repo", accountID: 7, jobsComplete: true, in: context)
        #expect(entity.measuredDurationSeconds == 120)
        _ = try WorkflowHistoryStore.upsert(run: run, jobs: [completedJob, self.job(id: 102)], repository: "example/repo", accountID: 7, jobsComplete: true, in: context)
        #expect(entity.completedAt == nil && entity.measuredDurationSeconds == nil)
    }

    @Test("Unsafe repository identifiers never create history", arguments: ["../repo", "example/repo/extra", "example/repo?token=value"])
    func unsafeRepository(_ repository: String) throws {
        let context = try makeContext()
        #expect(throws: WorkflowHistoryError.invalidRepository) {
            try WorkflowHistoryStore.upsert(run: workflow(attempt: 1), jobs: [], repository: repository, accountID: 7, in: context)
        }
        #expect(!context.hasChanges)
    }

    @Test("Duplicate jobs and jobs without a known attempt cannot be attributed to a guessed attempt")
    func ambiguousJobs() throws {
        let context = try makeContext()
        #expect(throws: WorkflowHistoryError.inconsistentPayload) {
            try WorkflowHistoryStore.upsert(run: workflow(attempt: nil), jobs: [job(id: 100)], repository: "example/repo", accountID: 7, in: context)
        }
        #expect(throws: WorkflowHistoryError.inconsistentPayload) {
            try WorkflowHistoryStore.upsert(run: workflow(attempt: 1), jobs: [job(id: 100), job(id: 100)], repository: "example/repo", accountID: 7, in: context)
        }
        #expect(!context.hasChanges)
    }

    @Test("Foreign job payloads are rejected before inserting any history")
    func foreignJobs() throws {
        let context = try makeContext()
        #expect(throws: WorkflowHistoryError.inconsistentPayload) {
            try WorkflowHistoryStore.upsert(run: workflow(attempt: 1), jobs: [job(id: 100, runID: 999)], repository: "example/repo", accountID: 7, in: context)
        }
        #expect(try context.fetchCount(FetchDescriptor<JobRunEntity>()) == 0)
    }

    @Test("A cancelled refresh cannot write history")
    func cancelledWrite() async throws {
        let context = try makeContext()
        let run = try workflow(attempt: 1)
        let task = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            return try WorkflowHistoryStore.upsert(run: run, jobs: [], repository: "example/repo", accountID: 7, in: context).id
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try context.fetchCount(FetchDescriptor<JobRunEntity>()) == 0)
    }

    private func makeContext() throws -> ModelContext {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        return container.mainContext
    }

    private func workflow(attempt: Int?) throws -> GitHubWorkflowRunDTO {
        let attemptJSON = attempt.map(String.init) ?? "null"
        return try JSONDecoder().decode(GitHubWorkflowRunDTO.self, from: Data("{\"id\":42,\"name\":\"CI\",\"status\":\"queued\",\"run_attempt\":\(attemptJSON)}".utf8))
    }

    private func job(id: Int64, runID: Int64 = 42) throws -> GitHubWorkflowJobDTO {
        try JSONDecoder().decode(GitHubWorkflowJobDTO.self, from: Data("{\"id\":\(id),\"run_id\":\(runID),\"name\":\"Build\",\"status\":\"queued\"}".utf8))
    }
}
