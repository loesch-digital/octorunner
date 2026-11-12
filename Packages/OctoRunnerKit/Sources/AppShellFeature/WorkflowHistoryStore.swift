import CoreModels
import Foundation
import GitHubAPI
import SwiftData

/// Models stay on their context's executor; network actors only supply values.
@MainActor
public enum WorkflowHistoryStore {
    @discardableResult
    public static func upsert(run: GitHubWorkflowRunDTO, jobs: [GitHubWorkflowJobDTO],
        repository: String, accountID: Int64, jobsComplete: Bool = false,
        in context: ModelContext) throws -> JobRunEntity {
        try Task.checkCancellation()
        let repository = try canonicalRepository(repository)
        guard accountID > 0, run.id > 0, run.runAttempt.map({ $0 > 0 }) ?? true,
              jobs.allSatisfy({ $0.runID == run.id && $0.id > 0 }),
              Set(jobs.map(\.id)).count == jobs.count,
              jobs.isEmpty || run.runAttempt != nil else { throw WorkflowHistoryError.inconsistentPayload }

        let runID = run.id
        let records = try context.fetch(FetchDescriptor<JobRunEntity>(predicate: #Predicate {
            $0.accountGitHubUserID == accountID && $0.repositoryFullName == repository && $0.githubRunId == runID
        }))
        let workflow = record(jobID: nil, attempt: run.runAttempt, from: records, in: context)
        update(workflow, run: run, repository: repository, accountID: accountID)
        // updated_at is not a completion timestamp. Only a complete job response
        // can establish the end of a completed workflow's execution interval.
        if jobsComplete {
            workflow.completedAt = run.status == "completed" && !jobs.isEmpty && jobs.allSatisfy({ $0.status == "completed" && $0.completedAt != nil })
                ? jobs.compactMap(\.completedAt).max() : nil
        }
        for job in jobs {
            let entity = record(jobID: job.id, attempt: run.runAttempt, from: records, in: context)
            update(entity, run: run, repository: repository, accountID: accountID)
            entity.recordKindRaw = "job"
            entity.githubJobId = job.id
            entity.jobName = job.name
            entity.statusRaw = job.status
            entity.conclusion = job.conclusion
            entity.createdAt = job.createdAt
            entity.actualStartedAt = job.startedAt
            entity.completedAt = job.completedAt
            entity.htmlURLString = job.htmlURL?.absoluteString
            entity.githubRunnerIDSnapshot = job.runnerID.flatMap { $0 > 0 ? $0 : nil }
            entity.runnerNameSnapshot = job.runnerName.flatMap { $0.isEmpty ? nil : $0 }
            // Keep remote history independent of deleting a local runner. The
            // existing cascade relationship still applies to legacy local jobs.
        }
        try context.save()
        return workflow
    }

    private static func record(jobID: Int64?, attempt: Int?, from records: [JobRunEntity], in context: ModelContext) -> JobRunEntity {
        if let entity = records.first(where: {
            $0.sourceRaw == "github" && $0.runAttempt == attempt && $0.githubJobId == jobID && $0.recordKindRaw == (jobID == nil ? "workflow" : "job")
        }) { return entity }
        let entity = JobRunEntity(githubRunId: 0, workflowName: "", repositoryFullName: "", branchName: "", commitSha: "", statusRaw: "unknown")
        context.insert(entity)
        return entity
    }

    private static func update(_ entity: JobRunEntity, run: GitHubWorkflowRunDTO, repository: String, accountID: Int64) {
        entity.sourceRaw = "github"
        entity.accountGitHubUserID = accountID
        entity.githubRunId = run.id
        entity.runAttempt = run.runAttempt
        entity.workflowName = run.name ?? ""
        entity.repositoryFullName = repository
        entity.branchName = run.headBranch ?? ""
        entity.commitSha = run.headSHA ?? ""
        entity.statusRaw = run.status ?? "unknown"
        entity.conclusion = run.conclusion
        entity.createdAt = run.createdAt
        entity.actualStartedAt = run.startedAt
        entity.event = run.event
        entity.htmlURLString = run.htmlURL?.absoluteString
    }

    private static func canonicalRepository(_ value: String) throws -> String {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        guard components.count == 2, components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(allowed.contains) }) else {
            throw WorkflowHistoryError.invalidRepository
        }
        return value.lowercased()
    }
}
