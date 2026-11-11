import Foundation
import RunnerEngine
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
        let provisioner = RunnerProvisionerActor(baseRunnersDirectory: managed)
        var rejected = false
        do {
            _ = try await provisioner.migrateImportedRunnerDirectory(runnerName: name, sourceRootDirectory: source, registerLaunchAgent: false)
        } catch { rejected = true }
        #expect(rejected)
        #expect(FileManager.default.fileExists(atPath: managed.path(percentEncoded: false)) == false)
        #expect((try? Data(contentsOf: sentinel)) == Data("original".utf8))
    }

    @Test("Import preserves an existing managed runner instead of replacing its files")
    func destinationCollision() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source")
        let managed = root.appending(path: "managed")
        let destination = managed.appending(path: "runner one")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let sentinel = destination.appending(path: "keep")
        try Data("original".utf8).write(to: sentinel)
        let provisioner = RunnerProvisionerActor(baseRunnersDirectory: managed)
        var rejected = false
        do {
            _ = try await provisioner.migrateImportedRunnerDirectory(runnerName: "runner one", sourceRootDirectory: source, registerLaunchAgent: false)
        } catch { rejected = true }
        #expect(rejected)
        #expect((try? Data(contentsOf: sentinel)) == Data("original".utf8))
    }
}
