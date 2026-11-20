import Foundation
@testable import RunnerEngine
import Testing

struct RunnerMigrationSafetyTests {
    @Test("Import rejects path components before touching the destination", arguments: ["../outside", "nested/runner", ".", "..", "", "runner\\name", "runner\nname"])
    func invalidNames(_ name: String) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        let managed = root.appending(path: "managed")
        let outside = root.appending(path: "outside")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let sentinel = outside.appending(path: "keep")
        try Data("original".utf8).write(to: sentinel)
        let request = RunnerMigrationRequest(runnerID: UUID(), name: name, remoteRunnerID: 21, sourceDirectory: source,
            scope: try #require(URL(string: "https://github.com/example/runner-repo")), labels: [], accountKey: "fixture",
            launchAgent: false)
        var rejected = false
        do {
            _ = try await Self.preflight(base: managed).prepare(request)
        } catch RunnerEngineError.invalidRunnerName {
            rejected = true
        }
        #expect(rejected)
        #expect(FileManager.default.fileExists(atPath: managed.path(percentEncoded: false)) == false)
        #expect((try? Data(contentsOf: sentinel)) == Data("original".utf8))
    }

    @Test("Import preserves an existing managed runner instead of replacing its files")
    func destinationCollision() async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let destination = fixture.managed.appending(path: request.name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appending(path: "keep")
        try Data("original".utf8).write(to: sentinel)
        var rejected = false
        do {
            _ = try await Self.preflight(base: fixture.managed).prepare(request)
        } catch RunnerEngineError.runnerDirectoryAlreadyExists {
            rejected = true
        }
        #expect(rejected)
        #expect((try? Data(contentsOf: sentinel)) == Data("original".utf8))
    }

    private static func preflight(base: URL) -> RunnerMigrationPreflight {
        RunnerMigrationPreflight(baseRunnersDirectory: base, fetchRemote: { _, _ in
            Issue.record("Rejected local paths must never reach GitHub")
            return nil
        }, fetchGroup: { _, _, _ in nil }, sampleProcesses: { [:] })
    }
}
