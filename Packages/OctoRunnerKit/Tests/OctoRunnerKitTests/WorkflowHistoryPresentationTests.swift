import CoreModels
import Foundation
import Testing
@testable import AppShellFeature

@MainActor
struct WorkflowHistoryPresentationTests {
    @Test("Pending history explicitly loses live status when observations expire")
    func freshness() {
        let model = fixture()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        model.observedAt = now
        #expect(WorkflowHistoryPresentation(entry: WorkflowHistoryEntry(model), now: now, locale: Locale(identifier: "de")).status == "Läuft")
        let expired = WorkflowHistoryPresentation(entry: WorkflowHistoryEntry(model), now: now.addingTimeInterval(91), locale: Locale(identifier: "de"))
        #expect(expired.status == "Veraltet")
        #expect(expired.symbol == "clock.badge.questionmark")
        model.statusRaw = "completed"
        model.conclusion = "success"
        #expect(WorkflowHistoryPresentation(entry: WorkflowHistoryEntry(model), now: now.addingTimeInterval(91), locale: Locale(identifier: "en")).status == "Succeeded")
    }

    @Test("History links accept only the exact GitHub repository and run, never arbitrary payload URLs")
    func links() {
        let model = fixture()
        for value in ["file:///tmp/private", "https://evil.example/owner/repo/actions/runs/42", "https://github.com/owner/other/actions/runs/42", "https://synthetic@github.com/owner/repo/actions/runs/42", "https://github.com/owner/repo/actions/runs/43", "https://github.com/owner/repo/actions/runs/42?token=synthetic"] {
            model.htmlURLString = value
            #expect(WorkflowHistoryPresentation(entry: WorkflowHistoryEntry(model)).githubURL == nil)
        }
        model.htmlURLString = "https://github.com/owner/repo/actions/runs/42/attempts/2"
        #expect(WorkflowHistoryPresentation(entry: WorkflowHistoryEntry(model)).githubURL?.absoluteString == model.htmlURLString)
    }

    @Test("Elapsed run and job durations require a fresh start and leave completed measurements unchanged")
    func elapsedRunDuration() {
        let model = fixture()
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        model.observedAt = now
        model.actualStartedAt = now.addingTimeInterval(-72)
        let running = WorkflowHistoryEntry(model)
        #expect(running.elapsedDuration(at: now) == 72)
        #expect(running.elapsedDuration(at: now.addingTimeInterval(4)) == 76)
        #expect(running.elapsedDuration(at: now.addingTimeInterval(91)) == nil)
        #expect(running.elapsedDuration(at: now.addingTimeInterval(-90)) == nil)

        model.recordKindRaw = "job"
        #expect(WorkflowHistoryEntry(model).elapsedDuration(at: now) == 72)
        model.statusRaw = "queued"
        #expect(WorkflowHistoryEntry(model).elapsedDuration(at: now) == nil)
        model.statusRaw = "completed"
        model.completedAt = now.addingTimeInterval(-12)
        #expect(WorkflowHistoryEntry(model).elapsedDuration(at: now) == 60)
    }

    @Test("An active step advances from its start without using a missing or future timestamp")
    func elapsedStepDuration() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let active = WorkflowJobStep(number: 1, name: "Test", status: "in_progress", conclusion: nil,
            startedAt: now.addingTimeInterval(-32), completedAt: nil)
        let notStarted = WorkflowJobStep(number: 2, name: "Archive", status: "pending", conclusion: nil,
            startedAt: nil, completedAt: nil)
        #expect(active.elapsedDuration(at: now) == 32)
        #expect(active.elapsedDuration(at: now.addingTimeInterval(-40)) == nil)
        #expect(notStarted.elapsedDuration(at: now) == nil)
        #expect(active.durationSeconds == nil)
    }

    private func fixture() -> JobRunEntity {
        let result = JobRunEntity(githubRunId: 42, workflowName: "Build", repositoryFullName: "owner/repo", branchName: "main", commitSha: "abcdef", statusRaw: "in_progress")
        result.sourceRaw = "github"
        result.runAttempt = 2
        return result
    }
}
