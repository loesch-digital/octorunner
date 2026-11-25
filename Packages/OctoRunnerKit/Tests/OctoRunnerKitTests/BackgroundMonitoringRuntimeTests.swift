import BackgroundMonitoringKit
import Foundation
import Testing

struct BackgroundMonitoringRuntimeTests {
    @Test func replacingConfigurationKeepsOnlyTheCurrentRevision() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitoringSnapshotStore(directory: directory)
        let original = MonitoringConfiguration(runnerIDs: [UUID()])
        let updated = MonitoringConfiguration(runnerIDs: [])
        #expect(try store.readConfiguration() == nil)
        try store.writeConfiguration(original)
        #expect(try store.readConfiguration() == original)
        try store.writeConfiguration(updated)
        #expect(try store.readConfiguration() == updated)
    }

    @Test func incompatibleAndMalformedConfigurationsAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "configuration.json")
        let store = MonitoringSnapshotStore(directory: directory)

        try Data(#"{"version":99}"#.utf8).write(to: file)
        #expect(throws: MonitoringSnapshotStore.SnapshotError.unsupportedVersion(99)) {
            try store.readConfiguration()
        }
        try Data("broken".utf8).write(to: file)
        #expect(throws: DecodingError.self) {
            try store.readConfiguration()
        }
    }

    @Test func exclusiveLeaseReleasesEvenWhenWorkThrows() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lease = MonitoringLease(lockFile: directory.appending(path: "monitoring.lock"))

        await #expect(throws: CancellationError.self) {
            try await lease.withOwnership {
                let competingOwner = try await lease.withOwnership { true }
                #expect(competingOwner == nil)
                throw CancellationError()
            } as Bool?
        }
        let newOwner = try await lease.withOwnership { true }
        #expect(newOwner == true)
    }

    @Test func observationRequiresCurrentRevisionAndFreshTimestamp() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitoringSnapshotStore(directory: directory)
        let runnerID = UUID()
        let configuration = MonitoringConfiguration(runnerIDs: [runnerID])
        let now = Date(timeIntervalSince1970: 1_000)
        let observation = MonitoringObservation(
            configurationRevision: configuration.revision,
            observedAt: now,
            statuses: [runnerID: .busy]
        )

        try store.writeConfiguration(configuration)
        try store.writeObservation(observation)
        #expect(try store.readObservation(for: configuration, at: now) == observation)
        #expect(try store.readObservation(for: configuration, at: now.addingTimeInterval(61)) == nil)
        #expect(try store.readObservation(for: configuration, at: now.addingTimeInterval(-6)) == nil)
        let changed = MonitoringConfiguration(runnerIDs: [runnerID])
        #expect(try store.readObservation(for: changed, at: now) == nil)
    }

    @Test func competingProcessCannotLockUntilOwnerReturns() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lock = directory.appending(path: "monitoring.lock")
        let lease = MonitoringLease(lockFile: lock)
        let whileOwned = try await lease.withOwnership {
            try Self.attemptChildLock(at: lock)
        }
        #expect(whileOwned == 75)
        #expect(try Self.attemptChildLock(at: lock) == 0)
    }

    private static func attemptChildLock(at url: URL) throws -> Int32 {
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        child.arguments = [
            "-MFcntl=:flock",
            "-e",
            #"open my $file, "+<", $ARGV[0] or exit 74; exit(flock($file, LOCK_EX | LOCK_NB) ? 0 : 75);"#,
            url.path
        ]
        try child.run()
        child.waitUntilExit()
        return child.terminationStatus
    }
}
