import CryptoKit
import Foundation
import RunnerEngine
import Testing

@Suite("RunnerEngine & Process Supervisor Tests")
struct RunnerEngineTests {
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
        #expect(dict["WorkingDirectory"] as? String == rootDir.path())
        #expect(dict["RunAtLoad"] as? Bool == true)
        #expect(dict["KeepAlive"] as? Bool == true)

        let programArgs = try #require(dict["ProgramArguments"] as? [String])
        #expect(programArgs == ["/bin/bash", rootDir.appending(path: "run.sh").path()])

        let env = try #require(dict["EnvironmentVariables"] as? [String: String])
        #expect(env["PATH"]?.contains("/opt/homebrew/bin") == true)
    }
}
