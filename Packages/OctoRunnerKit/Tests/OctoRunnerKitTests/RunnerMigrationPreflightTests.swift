import CoreModels
import Foundation
@testable import RunnerEngine
import SyncKit
import Testing

struct RunnerMigrationPreflightTests {
    @Test("Migration preparation reads the selected identity without reading or copying credentials")
    func readsOnlyRunnerMetadata() throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let credential = fixture.source.appending(path: ".credentials_rsaparams")
        try FileManager.default.createSymbolicLink(
            at: credential,
            withDestinationURL: fixture.directory.appending(path: "unavailable")
        )

        let snapshot = try RunnerMigrationSource.inspect(fixture.source)

        #expect(snapshot.configuration.agentId == 21)
        #expect(snapshot.configuration.agentName == "macbook-pro")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: credential.path)
            == fixture.directory.appending(path: "unavailable").path)
        #expect(try Set(FileManager.default.contentsOfDirectory(atPath: fixture.directory.path)) == ["source"])
    }

    @Test("Migration preparation rejects a symbolic link as the selected folder or its metadata")
    func rejectsSymbolicLinks() throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let alternate = fixture.directory.appending(path: "alternate")
        try FileManager.default.createSymbolicLink(at: alternate, withDestinationURL: fixture.source)
        #expect(throws: RunnerMigrationError.unverifiedSource) { try RunnerMigrationSource.inspect(alternate) }

        let movedMetadata = fixture.directory.appending(path: "metadata")
        try FileManager.default.moveItem(at: fixture.metadata, to: movedMetadata)
        try FileManager.default.createSymbolicLink(at: fixture.metadata, withDestinationURL: movedMetadata)
        #expect(throws: RunnerMigrationError.unverifiedSource) { try RunnerMigrationSource.inspect(fixture.source) }
    }

    @Test("Confirmation is invalidated when the source folder or metadata inode is replaced")
    func rejectsReplacement() throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let initial = try RunnerMigrationSource.inspect(fixture.source)
        // Keep the old inode allocated so this test can distinguish a replacement.
        let oldMetadata = fixture.directory.appending(path: "old-metadata")
        try FileManager.default.moveItem(at: fixture.metadata, to: oldMetadata)
        try FileManager.default.copyItem(at: oldMetadata, to: fixture.metadata)
        #expect(throws: RunnerMigrationError.sourceChanged) { try initial.revalidate() }

        let replacement = try RunnerMigrationSource.inspect(fixture.source)
        let oldRoot = fixture.directory.appending(path: "old-source")
        try FileManager.default.moveItem(at: fixture.source, to: oldRoot)
        try FileManager.default.copyItem(at: oldRoot, to: fixture.source)
        #expect(throws: RunnerMigrationError.sourceChanged) { try replacement.revalidate() }
    }

    @Test("Untrusted scope URLs are rejected before they can be used for GitHub lookups", arguments: [
        "http://github.com/example/runner-repo",
        "https://github.com.evil.example/example/runner-repo",
        "https://person@github.com/example/runner-repo",
        "https://github.com/example/runner-repo/issues",
        "https://github.com/example/runner-repo?name=other",
        "https://github.com/example%2Frunner-repo",
        "https://github.com/example/.."
    ])
    func rejectsUntrustedScope(_ scope: String) throws {
        let fixture = try MigrationSourceFixture(scope: scope)
        defer { fixture.remove() }
        #expect(throws: RunnerMigrationError.unverifiedSource) { try RunnerMigrationSource.inspect(fixture.source) }
    }

    @Test("A migration must not silently turn ephemeral or pinned runners into standard runners",
          arguments: ["ephemeral", "disableUpdate"])
    func rejectsNonstandardPolicy(_ policy: String) throws {
        let fixture = try MigrationSourceFixture(policy: policy)
        defer { fixture.remove() }
        #expect(throws: RunnerMigrationError.unsupportedSourcePolicy) {
            try RunnerMigrationSource.inspect(fixture.source)
        }
    }

    @Test("An installed GitHub launchd service must be retired before replacing the runner")
    func rejectsInstalledSourceService() async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        try Data().write(to: fixture.source.appending(path: ".service"))
        let preflight = RunnerMigrationPreflight(baseRunnersDirectory: fixture.managed, fetchRemote: { _, _ in
            Issue.record("GitHub must not be queried until the local service is retired")
            return nil
        }, fetchGroup: { _, _, _ in nil }, sampleProcesses: { [:] })
        let request = try fixture.request()
        await #expect(throws: RunnerMigrationError.sourceServiceInstalled) { try await preflight.prepare(request) }
    }

    @Test("Preflight confirms scoped identity, group and labels without creating the destination")
    func verifiedPlan() async throws {
        let fixture = try MigrationSourceFixture(scope: "https://github.com/example")
        defer { fixture.remove() }
        let request = try fixture.request(scope: "https://github.com/Example/", labels: ["macos", "Xcode"])
        let remote = try Self.remote()
        let group = RunnerMigrationGroup(id: 3, name: "Build")
        let preflight = RunnerMigrationPreflight(
            baseRunnersDirectory: fixture.managed,
            fetchRemote: { config, account in
                #expect(account == "account-key")
                #expect(config.agentId == 21)
                return remote
            },
            fetchGroup: { _, _, _ in group },
            sampleProcesses: { [:] }
        )
        let plan = try await preflight.prepare(request)

        #expect(plan.runnerID == request.runnerID)
        #expect(plan.destination.path == fixture.managed.appending(path: request.name).path)
        #expect(plan.group == group)
        #expect(plan.customLabels == ["xcode"])
        #expect(!FileManager.default.fileExists(atPath: fixture.managed.path))
    }

    @Test("An active, unidentifiable or inaccessible runner cannot proceed", arguments: [
        RunnerMigrationError.runnerBusy, .listenerStillRunning, .runnerNotAccessible, .runnerIdentityMismatch,
        .labelsChanged, .incompatibleRunnerLabels
    ])
    func rejectsUnsafeStates(_ expected: RunnerMigrationError) async throws {
        let fixture = try MigrationSourceFixture()
        defer { fixture.remove() }
        let request = try fixture.request()
        let remote = try Self.remote(name: expected == .runnerIdentityMismatch ? "another-runner" : "macbook-pro",
                                     busy: expected == .runnerBusy,
                                     architecture: expected == .incompatibleRunnerLabels ? "X64" : "ARM64")
        let preflight = RunnerMigrationPreflight(
            baseRunnersDirectory: fixture.managed,
            fetchRemote: { _, _ in expected == .runnerNotAccessible ? nil : remote },
            fetchGroup: { _, _, _ in
                Issue.record("Repository runners have no organization runner group")
                return nil
            },
            sampleProcesses: {
                expected == .listenerStillRunning
                    ? [fixture.source.path: RunnerProcessPresence(listenerPID: 42)] : [:]
            }
        )
        let candidate = expected == .labelsChanged ? try fixture.request(labels: ["macos", "another-label"]) : request
        await #expect(throws: expected) { try await preflight.prepare(candidate) }
        #expect(!FileManager.default.fileExists(atPath: fixture.managed.path))
    }

    private static func remote(name: String = "macbook-pro", busy: Bool = false, architecture: String = "ARM64") throws -> GitHubRemoteRunnerDTO {
        let json = """
        {"id":21,"name":"\(name)","os":"osx","status":"offline","busy":\(busy),"labels":[
          {"name":"self-hosted","type":"read-only"},{"name":"macOS","type":"read-only"},
          {"name":"\(architecture)","type":"read-only"},{"name":"xcode","type":"custom"}
        ]}
        """
        return try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: Data(json.utf8))
    }
}

struct MigrationSourceFixture {
    let directory = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    var source: URL { directory.appending(path: "source", directoryHint: .isDirectory) }
    var metadata: URL { source.appending(path: ".runner") }
    var managed: URL { directory.appending(path: "managed", directoryHint: .isDirectory) }

    init(scope: String = "https://github.com/example/runner-repo", policy: String? = nil) throws {
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let flags = policy.map { ",\"\($0)\":true" } ?? ""
        let config = """
        {"agentId":21,"agentName":"macbook-pro","poolId":3,"poolName":"Build","gitHubUrl":"\(scope)","workFolder":"_work"\(flags)}
        """
        try (Data([0xef, 0xbb, 0xbf]) + Data(config.utf8)).write(to: metadata)
    }

    func request(
        scope: String = "https://github.com/example/runner-repo",
        labels: [String] = ["macos", "xcode"]
    ) throws -> RunnerMigrationRequest {
        RunnerMigrationRequest(
            runnerID: UUID(), name: "macbook-pro", remoteRunnerID: 21,
            sourceDirectory: source, scope: try #require(URL(string: scope)), labels: labels,
            accountKey: "account-key", launchAgent: true
        )
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
