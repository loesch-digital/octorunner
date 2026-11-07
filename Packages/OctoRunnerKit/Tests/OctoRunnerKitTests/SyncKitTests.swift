import CoreModels
import Foundation
import SyncKit
import Testing

@Suite("SyncKit — Local Runner Discovery & GitHub Reconciliation Tests")
struct SyncKitTests {
    @Test("LocalDotRunnerConfig strips .NET UTF-8 BOM (0xEF 0xBB 0xBF) and infers repository vs org scope")
    func dotRunnerBOMDecodingAndScopeInference() throws {
        let jsonString = """
        {
          "agentId": 21,
          "agentName": "macbook-pro-frank",
          "poolId": 1,
          "poolName": "Default",
          "serverUrl": "https://pipelinesghubeus25.actions.githubusercontent.com/test/",
          "gitHubUrl": "https://github.com/loesch-digital/itemflux-ios-app",
          "workFolder": "_work",
          "useV2Flow": true
        }
        """
        var bomPrefixedData = Data([0xEF, 0xBB, 0xBF])
        bomPrefixedData.append(jsonString.data(using: .utf8)!)

        let decoded = try LocalDotRunnerConfig.decode(from: bomPrefixedData)
        #expect(decoded.agentId == 21)
        #expect(decoded.agentName == "macbook-pro-frank")
        #expect(decoded.workFolder == "_work")
        #expect(decoded.inferredScopeType == .repository)
        #expect(decoded.ownerAndRepo?.owner == "loesch-digital")
        #expect(decoded.ownerAndRepo?.repo == "itemflux-ios-app")

        let orgJSON = """
        {
          "agentId": 99,
          "agentName": "org-runner-1",
          "gitHubUrl": "https://github.com/loesch-digital",
          "workFolder": "_work"
        }
        """.data(using: .utf8)!
        let orgConfig = try LocalDotRunnerConfig.decode(from: orgJSON)
        #expect(orgConfig.inferredScopeType == .organization)
        #expect(orgConfig.ownerAndRepo?.owner == "loesch-digital")
        #expect(orgConfig.ownerAndRepo?.repo == nil)
    }

    @Test("LocalRunnerDiscoveryActor parses ps -axo output to detect Runner.Listener and Runner.Worker PIDs")
    func processTableOutputParsing() {
        let samplePSOutput = """
          102 /sbin/launchd
        87558 /Users/frank/Documents/apps/actions-runner/bin/Runner.Listener run
        91204 /Users/frank/Documents/apps/busy-runner/bin.2.338.2/Runner.Listener run
        91210 /Users/frank/Documents/apps/busy-runner/bin.2.338.2/Runner.Worker spawnclient 10 11
        """

        let parsed = LocalRunnerDiscoveryActor.parseProcessTable(samplePSOutput)
        #expect(parsed.count == 2)

        let idleRunner = parsed["/Users/frank/Documents/apps/actions-runner"]
        #expect(idleRunner?.listenerPID == 87558)
        #expect(idleRunner?.isWorkerActive == false)

        let busyRunner = parsed["/Users/frank/Documents/apps/busy-runner"]
        #expect(busyRunner?.listenerPID == 91204)
        #expect(busyRunner?.isWorkerActive == true)
    }

    @Test("LocalRunnerDiscoveryActor inspects runner folder with BOM .runner file and bin version symlink")
    func filesystemRunnerDiscoveryInTempDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appending(path: "OctoRunnerSyncTest-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let binVersionDir = tempDir.appending(path: "bin.2.338.2", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: binVersionDir, withIntermediateDirectories: true)
        let binSymlink = tempDir.appending(path: "bin")
        try FileManager.default.createSymbolicLink(at: binSymlink, withDestinationURL: binVersionDir)

        let dotRunnerJSON = """
        {
          "agentId": 21,
          "agentName": "macbook-pro-frank",
          "poolId": 1,
          "poolName": "Default",
          "gitHubUrl": "https://github.com/loesch-digital/itemflux-ios-app",
          "workFolder": "_work"
        }
        """
        var bomData = Data([0xEF, 0xBB, 0xBF])
        bomData.append(dotRunnerJSON.data(using: .utf8)!)
        try bomData.write(to: tempDir.appending(path: ".runner"))

        let actor = LocalRunnerDiscoveryActor()
        let activeMap: [String: LocalRunnerProcessState] = [
            LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: tempDir): LocalRunnerProcessState(listenerPID: 87558, isWorkerActive: false)
        ]

        let discovered = await actor.inspectRunnerDirectory(at: tempDir, activeProcesses: activeMap)
        #expect(discovered != nil)
        #expect(discovered?.config.agentId == 21)
        #expect(discovered?.config.agentName == "macbook-pro-frank")
        #expect(discovered?.runnerVersion == "2.338.2")
        #expect(discovered?.listenerPID == 87558)
        #expect(discovered?.localStatus == .idle)
    }

    @Test("GitHubRemoteRunnerDTO decodes GitHub Actions runner API response and extracts label names")
    func githubRemoteRunnerDTODecoding() throws {
        let json = """
        {
          "id": 21,
          "name": "macbook-pro-frank",
          "os": "macOS",
          "status": "online",
          "busy": false,
          "labels": [
            { "id": 1, "name": "self-hosted", "type": "read-only" },
            { "id": 2, "name": "macOS", "type": "read-only" },
            { "id": 3, "name": "ARM64", "type": "read-only" },
            { "id": 4, "name": "ios-build", "type": "custom" }
          ]
        }
        """.data(using: .utf8)!

        let dto = try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: json)
        #expect(dto.id == 21)
        #expect(dto.name == "macbook-pro-frank")
        #expect(dto.status == "online")
        #expect(dto.busy == false)
        #expect(dto.labelNames == ["self-hosted", "macOS", "ARM64", "ios-build"])
    }
}
