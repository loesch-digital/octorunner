import CoreModels
import Foundation
import SwiftData
import Testing

/// Opt-in fixture generation, only usable while checked out at the old schema.
struct LegacyFixtureGenerator {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["OCTORUNNER_LEGACY_FIXTURE_DIR"] != nil))
    @MainActor
    func generate() throws {
        let entity = try #require(OctoRunnerPersistence.schema.entities.first { $0.name == "JobRunEntity" })
        let fields = Set(entity.properties.map(\.name))
        let originalFields: Set<String> = ["id", "githubRunId", "workflowName", "repositoryFullName", "branchName", "commitSha", "statusRaw", "startedAt", "durationSeconds", "runner"]
        try #require(fields == originalFields, "Regenerate using the original schema revision; never overwrite the fixture with the new model")
        let directory = try #require(ProcessInfo.processInfo.environment["OCTORUNNER_LEGACY_FIXTURE_DIR"])
        let root = URL(filePath: directory, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "v0_4.store")
        try #require(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        let schema = OctoRunnerPersistence.schema
        let container = try ModelContainer(for: schema, configurations: [ModelConfiguration(schema: schema, url: url)])
        let context = container.mainContext
        let runner = RunnerEntity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000041")!, name: "fixture-runner", scopeUrl: URL(string: "https://github.com/example/fixture")!, workDirectory: URL(filePath: "/tmp/fixture-runner/_work"))
        runner.githubRunnerId = 41
        let job = JobRunEntity(id: UUID(uuidString: "00000000-0000-0000-0000-000000000042")!, githubRunId: 42, workflowName: "Legacy CI", repositoryFullName: "example/fixture", branchName: "main", commitSha: "fixture-sha", startedAt: Date(timeIntervalSince1970: 1_700_000_000), durationSeconds: 42, runner: runner)
        let account = GitHubAccountEntity(githubUserId: 43, login: "fixture-account", scopes: ["repo"], keychainAccountKey: "fixture-metadata-only")
        let audit = AuditLogEntity(title: "Fixture audit", summary: "Synthetic migration data", targetRunnerName: runner.name)
        context.insert(runner)
        context.insert(job)
        context.insert(account)
        context.insert(audit)
        try context.save()
    }
}
