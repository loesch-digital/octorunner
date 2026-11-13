import Foundation
import Darwin
@testable import RunnerEngine
import Testing

struct WorkspaceCleanerTests {
    private let now = Date(timeIntervalSince1970: 2_000_000_000)

    @Test("Cleaner measures real bytes and removes old stopped workspaces while retaining tools, configuration and newest log")
    func cleanup() async throws {
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: fixture.base)
        let snapshot = try await cleaner.inspect(runners: [fixture.runner], workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(snapshot.logicalBytesByCategory["workspaces"] == 8)
        #expect(Set(snapshot.candidates.map(\.relativePath)) == ["_work/repo", "_diag/Runner_old.log"])
        let report = try await cleaner.clean(snapshot.candidates, runners: [fixture.runner], checker: StorageStoppedChecker(stopped: true), workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(report.removedCount == 2)
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "_work/repo").path()))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "_work/_tool/cache").path()))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "_diag/Runner_newest.log").path()))
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: ".credentials").path()))
    }

    @Test("Loaded or unknown runner state never authorizes deletion")
    func activeRunner() async throws {
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: fixture.base)
        let snapshot = try await cleaner.inspect(runners: [fixture.runner], workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        let report = try await cleaner.clean(snapshot.candidates, runners: [fixture.runner], checker: StorageStoppedChecker(stopped: false), workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(report.removedCount == 0)
        #expect(report.skippedCount == snapshot.candidates.count)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "_work/repo/data").path()))
    }

    @Test("Symlink targets outside the managed roots are never measured or deleted")
    func symlinks() async throws {
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let outside = fixture.base.deletingLastPathComponent().appending(path: "outside-\(UUID())")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try Data(repeating: 1, count: 100).write(to: outside.appending(path: "keep"))
        try FileManager.default.createSymbolicLink(at: fixture.root.appending(path: "_work/linked"), withDestinationURL: outside)
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: fixture.base)
        let snapshot = try await cleaner.inspect(runners: [fixture.runner], workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(!snapshot.candidates.contains { $0.relativePath.contains("linked") })
        #expect(snapshot.logicalBytesByCategory["workspaces"] == 8)
        _ = try await cleaner.clean(snapshot.candidates, runners: [fixture.runner], checker: StorageStoppedChecker(stopped: true), workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(try Data(contentsOf: outside.appending(path: "keep")).count == 100)
    }

    @Test("A symlink ancestor above the managed base is rejected before measuring or deleting")
    func symlinkAncestor() async throws {
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let link = fixture.base.deletingLastPathComponent().appending(path: "storage-link-\(UUID())")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: fixture.base)
        defer { try? FileManager.default.removeItem(at: link) }
        let nestedBase = link.appending(path: "nested/runners")
        let root = nestedBase.appending(path: "runner")
        try FileManager.default.createDirectory(at: root.appending(path: "_work"), withIntermediateDirectories: true)
        let linkedRunner = ManagedStorageRunner(id: UUID(), root: root, serviceLabel: "io.octorunner.agent.fixture")
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: nestedBase)
        await #expect(throws: CocoaError.self) {
            try await cleaner.inspect(runners: [linkedRunner], workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        }
    }

    @Test("A change during the final asynchronous runner check is revalidated")
    func changedDuringStateCheck() async throws {
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: fixture.base)
        let snapshot = try await cleaner.inspect(runners: [fixture.runner], workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        let report = try await cleaner.clean(snapshot.candidates.filter { $0.relativePath == "_work/repo" }, runners: [fixture.runner], checker: StorageChangingChecker(file: fixture.root.appending(path: "_work/repo/data"), now: now), workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(report.removedCount == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "_work/repo/data").path()))
    }

    @Test("Unknown state, duplicate identities and a reached capacity target retain every item")
    func conservativeSkips() async throws {
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: fixture.base)
        let snapshot = try await cleaner.inspect(runners: [fixture.runner], workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        let unknown = try await cleaner.clean(snapshot.candidates, runners: [fixture.runner], checker: StorageUnknownChecker(), workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(unknown.removedCount == 0 && unknown.skippedCount == snapshot.candidates.count)
        let duplicate = try await cleaner.clean(snapshot.candidates, runners: [fixture.runner, fixture.runner], checker: StorageStoppedChecker(stopped: true), workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(duplicate.removedCount == 0)
        let capacity = try await cleaner.clean(snapshot.candidates, runners: [fixture.runner], checker: StorageStoppedChecker(stopped: true), workspaceAgeDays: 7, logRetentionDays: 14, now: now, stopWhenAvailableBytes: 0)
        #expect(capacity.removedCount == 0)
    }

    @Test("A workspace changed after preview is revalidated rather than removed")
    func changedSincePreview() async throws {
        let fixture = try StorageFixture(now: now)
        defer { fixture.remove() }
        let cleaner = WorkspaceCleanerActor(baseRunnersDirectory: fixture.base)
        let snapshot = try await cleaner.inspect(runners: [fixture.runner], workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        let candidates = snapshot.candidates.filter { $0.relativePath == "_work/repo" }
        #expect(candidates.count == 1)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: fixture.root.appending(path: "_work/repo/data").path())
        let report = try await cleaner.clean(candidates, runners: [fixture.runner], checker: StorageStoppedChecker(stopped: true), workspaceAgeDays: 7, logRetentionDays: 14, now: now)
        #expect(report.removedCount == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.root.appending(path: "_work/repo/data").path()))
    }
}

private actor StorageStoppedChecker: StorageRunnerStateChecking {
    let stopped: Bool
    init(stopped: Bool) { self.stopped = stopped }
    func isStopped(_ runner: ManagedStorageRunner) -> Bool { stopped }
}

struct StorageFixture {
    let base: URL
    let root: URL
    let runner: ManagedStorageRunner

    init(now: Date) throws {
        guard let canonical = realpath(FileManager.default.temporaryDirectory.path(), nil) else { throw CocoaError(.fileReadUnknown) }
        defer { free(canonical) }
        base = URL(fileURLWithPath: String(cString: canonical)).appending(path: "storage-fixture-\(UUID())")
        root = base.appending(path: "runner")
        runner = ManagedStorageRunner(id: UUID(), root: root, serviceLabel: "io.octorunner.agent.fixture")
        for (path, bytes) in [("_work/repo/data", 3), ("_work/_tool/cache", 5), ("_diag/Runner_old.log", 7), ("_diag/Runner_newest.log", 11), (".credentials", 13)] {
            let url = root.appending(path: path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: bytes).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(path.contains("newest") ? -1_000 : -3_000_000)], ofItemAtPath: url.path())
        }
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-3_000_000)], ofItemAtPath: root.appending(path: "_work/repo").path())
    }
    func remove() { try? FileManager.default.removeItem(at: base) }
}

private actor StorageChangingChecker: StorageRunnerStateChecking {
    let file: URL
    let now: Date
    var calls = 0
    init(file: URL, now: Date) { self.file = file; self.now = now }
    func isStopped(_ runner: ManagedStorageRunner) throws -> Bool {
        calls += 1
        if calls == 2 { try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: file.path()) }
        return true
    }
}
private actor StorageUnknownChecker: StorageRunnerStateChecking {
    func isStopped(_ runner: ManagedStorageRunner) throws -> Bool { throw CocoaError(.fileReadUnknown) }
}
