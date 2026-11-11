import CoreModels
import Foundation
import SyncKit
import Testing

@Suite("SyncKit — Local Runner Discovery & GitHub Reconciliation Tests")
struct SyncKitTests {
    @Test("Background log reads require a managed path; imported external paths wait for user action")
    func backgroundLogAccessPolicy() {
        let home = URL(fileURLWithPath: "/tmp/OctoRunnerPolicyHome", isDirectory: true).resolvingSymlinksInPath()
        #expect(RunnerDirectoryAccessPolicy.allowsAutomaticRead(at: home.appending(path: "actions-runner/_diag/Runner.log"), homeDirectory: home))
        #expect(RunnerDirectoryAccessPolicy.allowsAutomaticRead(at: home.appending(path: "Library/Application Support/io.octorunner.macos/runners/one/_diag"), homeDirectory: home))
        #expect(!RunnerDirectoryAccessPolicy.allowsAutomaticRead(at: home.appending(path: "Documents/actions-runner/_diag"), homeDirectory: home))
        #expect(!RunnerDirectoryAccessPolicy.allowsAutomaticRead(at: home.appending(path: "actions-runner-other/_diag"), homeDirectory: home))
        #expect(!RunnerDirectoryAccessPolicy.allowsAutomaticRead(at: home.appending(path: "actions-runner/../Documents/_diag"), homeDirectory: home))
    }

    @Test("Automatic discovery never reads external runner folders, including roots from live processes")
    func externalFoldersRequireExplicitSelection() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "OctoRunnerDiscovery-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let paths = ["actions-runner", ".octorunner/runners/managed", "Documents/apps/actions-runner",
                     "Documents/actions-runner", "Desktop/external-runner",
                     "Library/Application Support/io.octorunner.macos/runners/current-managed"]
        for (index, path) in paths.enumerated() {
            let directory = home.appending(path: path, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data("""
            {"agentId": \(index + 1), "agentName": "runner-\(index)",
             "gitHubUrl": "https://github.com/example/repo", "workFolder": "_work"}
            """.utf8).write(to: directory.appending(path: ".runner"))
        }
        let external = home.appending(path: "Desktop/external-runner", directoryHint: .isDirectory)
        let discovery = LocalRunnerDiscoveryActor(homeDirectory: home, processTableProvider: {
            [LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: external):
                LocalRunnerProcessState(listenerPID: 123, isWorkerActive: false)]
        })
        let automatic = await discovery.discoverAllLocalRunners()
        #expect(Set(automatic.map(\.config.agentName)) == ["runner-0", "runner-1", "runner-5"])

        let selected = await discovery.discoverAllLocalRunners(additionalDirectories: [external, external])
        #expect(Set(selected.map(\.config.agentName)) == ["runner-0", "runner-1", "runner-4", "runner-5"])
        #expect(selected.count == 4)
        #expect(selected.first(where: { $0.config.agentName == "runner-4" })?.listenerPID == 123)
    }

    @Test("Automatic discovery does not follow standard-folder symlinks into external folders")
    func automaticDiscoveryRejectsExternalSymlinks() async throws {
        let home = FileManager.default.temporaryDirectory
            .appending(path: "OctoRunnerSymlink-\(UUID().uuidString)", directoryHint: .isDirectory)
            .resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: home) }
        let external = home.appending(path: "Documents/external", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try Data("""
        {"agentId": 1, "agentName": "external", "gitHubUrl": "https://github.com/example/repo", "workFolder": "_work"}
        """.utf8).write(to: external.appending(path: ".runner"))
        try FileManager.default.createSymbolicLink(at: home.appending(path: "actions-runner"), withDestinationURL: external)
        let discovery = LocalRunnerDiscoveryActor(homeDirectory: home, processTableProvider: { [:] })
        #expect(await discovery.discoverAllLocalRunners().isEmpty)
        #expect(await discovery.discoverAllLocalRunners(additionalDirectories: [external]).count == 1)
    }

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
