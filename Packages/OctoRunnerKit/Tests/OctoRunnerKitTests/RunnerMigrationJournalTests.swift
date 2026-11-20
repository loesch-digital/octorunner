import Foundation
@testable import RunnerEngine
import Testing

struct RunnerMigrationJournalTests {
    @Test("An interrupted registration is visible to a new process with the known identities")
    func resumesRecoveryInformation() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = RunnerMigrationJournal(directory: directory)
        let entry = Self.entry()
        try journal.begin(entry)
        try journal.update(entry.at(.registering))
        let reopened = RunnerMigrationJournal(directory: directory)

        #expect(try reopened.pending(entry.runnerID) == entry.at(.registering))
        #expect(throws: RunnerMigrationError.recoveryRequired) { try reopened.begin(entry) }

        let registered = entry.at(.registered, newRemoteID: 37)
        try reopened.update(registered)
        #expect(try journal.pending(entry.runnerID)?.newRemoteID == 37)
        try reopened.complete(entry.runnerID)
        #expect(try journal.pending(entry.runnerID) == nil)
    }

    @Test("Unrecognized journals block another registration and stay intact")
    func damagedJournalIsNotReplaced() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = RunnerMigrationJournal(directory: directory)
        let entry = Self.entry()
        try journal.begin(entry)
        let existing = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        let damage = Data("partial write fixture".utf8)
        try damage.write(to: existing)

        #expect(throws: RunnerMigrationError.recoveryRequired) { try journal.pending(entry.runnerID) }
        #expect(throws: RunnerMigrationError.recoveryRequired) { try journal.begin(entry) }
        #expect(try Data(contentsOf: existing) == damage)
    }

    @Test("Discovery excludes both sides of an in-flight migration")
    func protectsPendingPaths() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = RunnerMigrationJournal(directory: directory)
        let entry = Self.entry()
        try journal.begin(entry)
        #expect(try journal.protectedPaths() == [entry.source.path, entry.destination.path])
        try journal.complete(entry.runnerID)
        #expect(try journal.protectedPaths().isEmpty)
    }

    private static func entry() -> RunnerMigrationRecovery {
        RunnerMigrationRecovery(
            runnerID: UUID(), oldRemoteID: 21, newRemoteID: nil,
            source: URL(filePath: "/Fixture/source"),
            destination: URL(filePath: "/Fixture/managed/runner"),
            stage: .preparing
        )
    }
}
