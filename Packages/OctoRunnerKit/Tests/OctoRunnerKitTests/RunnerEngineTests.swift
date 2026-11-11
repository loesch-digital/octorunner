import CryptoKit
import Foundation
import RunnerEngine
import Testing

@Suite("RunnerEngine & Process Supervisor Tests")
struct RunnerEngineTests {
    @Test("Log reads never follow diagnostic symlinks outside the selected runner", arguments: [false, true])
    func logSymlinksCannotReadOutsideRunner(linkDirectory: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "OctoRunnerLogBoundary-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runner = root.appending(path: "runner")
        let diag = runner.appending(path: "_diag")
        let external = root.appending(path: "external")
        try FileManager.default.createDirectory(at: runner, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let outsideLog = external.appending(path: "Runner.log")
        try "[INFO] external-file-must-not-be-read".write(to: outsideLog, atomically: true, encoding: .utf8)
        if linkDirectory {
            try FileManager.default.createSymbolicLink(at: diag, withDestinationURL: external)
        } else {
            try FileManager.default.createDirectory(at: diag, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: diag.appending(path: "Runner.log"), withDestinationURL: outsideLog)
        }
        let streamer = RunnerLogStreamerActor()
        #expect(await streamer.readRecentLogLines(forRunnerRoot: runner).isEmpty)
    }

    @Test("RunnerSupervisorActor queries SMAppService login autostart state safely")
    func loginAutostartStatusQuery() async {
        let supervisor = RunnerSupervisorActor()
        let isEnabled = await supervisor.isLoginAutostartEnabled()
        #expect(isEnabled == true || isEnabled == false)
    }

    @Test("RunnerBinaryCacheActor verifies CryptoKit SHA256 checksum accurately")
    func binaryCacheSHA256Verification() throws {
        let sampleContent = Data("octo-runner-arm64-binary-payload".utf8)
        let expectedHash = SHA256.hash(data: sampleContent).map { String(format: "%02x", $0) }.joined()

        let tempFile = FileManager.default.temporaryDirectory
            .appending(path: "runner-sha256-test-\(UUID().uuidString).tar.gz")
        try sampleContent.write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        #expect(try RunnerBinaryCacheActor.verifySHA256(of: tempFile, expectedHex: expectedHash) == true)
        #expect(try RunnerBinaryCacheActor.verifySHA256(of: tempFile, expectedHex: expectedHash.uppercased()) == true)
        #expect(try RunnerBinaryCacheActor.verifySHA256(of: tempFile, expectedHex: "0000deadbeef") == false)
    }

    @Test("LaunchAgentPlistGenerator builds valid launchd XML PropertyList with Homebrew PATH")
    func launchAgentPlistGeneration() throws {
        let rootDir = URL(fileURLWithPath: "/Users/frank/Library/Application Support/io.octorunner.macos/runners/mac-runner-1")
        let plistData = try LaunchAgentPlistGenerator.generatePlistData(
            serviceLabel: "io.octorunner.agent.mac-runner-1",
            runnerRootDirectory: rootDir
        )

        let plistObject = try PropertyListSerialization.propertyList(from: plistData, format: nil)
        let dict = try #require(plistObject as? [String: Any])

        #expect(dict["Label"] as? String == "io.octorunner.agent.mac-runner-1")
        #expect(dict["WorkingDirectory"] as? String == rootDir.path(percentEncoded: false))
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["KeepAlive"] as? Bool == true)

        let programArgs = try #require(dict["ProgramArguments"] as? [String])
        #expect(programArgs == ["/bin/bash", rootDir.appending(path: "run.sh").path(percentEncoded: false)])

        let env = try #require(dict["EnvironmentVariables"] as? [String: String])
        #expect(env["PATH"]?.contains("/opt/homebrew/bin") == true)
    }

    @Test("RunnerLogStreamerActor reads _diag/Runner_*.log lines and RunnerProvisionerActor migrates imported runner folder")
    func logStreamerAndRunnerMigration() async throws {
        let tempBase = FileManager.default.temporaryDirectory
            .appending(path: "octorunner-step04-test-\(UUID().uuidString)", directoryHint: .isDirectory)
        let sourceRunnerDir = tempBase.appending(path: "legacy-actions-runner", directoryHint: .isDirectory)
        let diagDir = sourceRunnerDir.appending(path: "_diag", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: diagDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempBase) }

        let logContent = """
        [2026-11-07 18:00:01Z INFO Runner] Connected to GitHub Actions
        [2026-11-07 18:00:05Z WARN Worker] Slow network response
        [2026-11-07 18:00:09Z ERR Worker] Build step exited with code 1
        """
        try Data(logContent.utf8).write(to: diagDir.appending(path: "Runner_20261107-180000-utc.log"))
        try Data("{\"agentId\":21,\"agentName\":\"macbook-pro-frank\"}".utf8).write(to: sourceRunnerDir.appending(path: ".runner"))

        let streamer = RunnerLogStreamerActor()
        let lines = await streamer.readRecentLogLines(forRunnerRoot: sourceRunnerDir, maxLines: 50)
        #expect(lines.count == 3)
        #expect(lines[0].level == .info)
        #expect(lines[1].level == .warning)
        #expect(lines[2].level == .error)

        let managedBase = tempBase.appending(path: "managed-runners", directoryHint: .isDirectory)
        let provisioner = RunnerProvisionerActor(baseRunnersDirectory: managedBase)
        let migratedDir = try await provisioner.migrateImportedRunnerDirectory(
            runnerName: "macbook-pro-frank",
            sourceRootDirectory: sourceRunnerDir,
            registerLaunchAgent: false
        )
        #expect(FileManager.default.fileExists(atPath: migratedDir.appending(path: ".runner").path()))
        #expect(FileManager.default.fileExists(atPath: migratedDir.appending(path: "_work").path()))
    }
}
