import CoreModels
import Foundation
@testable import RunnerEngine
import Testing

struct RunnerLaunchConfigurationTests {
    @Test("LaunchAgents apply keepalive and throttle policies without changing the required runner script interpreter", arguments: RunnerRestartPolicy.allCases)
    func recoveryPolicy(_ restart: RunnerRestartPolicy) throws {
        var policy = RunnerRuntimePolicy()
        policy.restartPolicy = restart
        policy.restartDelaySeconds = 23
        policy.shell = .zsh
        let config = RunnerLaunchConfiguration(runtimePolicy: policy, inheritHostPath: false, hostPath: "/unwanted/bin")
        let root = URL(fileURLWithPath: "/Users/test/Library/Application Support/runner one")
        let data = try LaunchAgentPlistGenerator.generatePlistData(serviceLabel: "io.octorunner.agent.test", runnerRootDirectory: root, configuration: config)
        let plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        #expect(plist["ThrottleInterval"] as? Int == 23)
        switch restart {
        case .always: #expect(plist["KeepAlive"] as? Bool == true)
        case .manual: #expect(plist["KeepAlive"] as? Bool == false)
        case .onNonZeroExit:
            #expect((plist["KeepAlive"] as? [String: Bool]) == ["SuccessfulExit": false])
        }
        #expect(plist["ProgramArguments"] as? [String] == ["/bin/bash", "/Users/test/Library/Application Support/runner one/run.sh"])
        #expect(plist["WorkingDirectory"] as? String == "/Users/test/Library/Application Support/runner one")
        let environment = try #require(plist["EnvironmentVariables"] as? [String: String])
        #expect(environment["SHELL"] == "/bin/zsh")
        #expect(environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect((plist["StandardOutPath"] as? String)?.contains("%20") == false)
    }

    @Test("Archive extraction accepts real filesystem paths containing spaces")
    func archivePaths() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "runner archive test \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "archive source")
        let destination = root.appending(path: "runner install")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try "fixture".write(to: source.appending(path: "payload"), atomically: true, encoding: .utf8)
        let archive = root.appending(path: "runner archive.tar.gz")
        let tar = Process()
        tar.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path(percentEncoded: false), "-C", source.path(percentEncoded: false), "payload"]
        try tar.run()
        tar.waitUntilExit()
        #expect(tar.terminationStatus == 0)
        try RunnerProvisionerActor.extractArchive(archiveURL: archive, into: destination)
        #expect(try String(contentsOf: destination.appending(path: "payload"), encoding: .utf8) == "fixture")
    }

    @Test("Inherited PATH rejects relative and empty entries and preserves valid precedence without duplicates")
    func safeHostPath() {
        let config = RunnerLaunchConfiguration(inheritHostPath: true, hostPath: ":./tools:/opt/custom:/usr/bin:/opt/custom:\n/tmp:/bin")
        #expect(config.environment["PATH"] == "/opt/custom:/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin:/usr/sbin:/sbin")
        #expect(config.environment["SHELL"] == "/bin/bash")
    }

    @Test("Launch settings validate their policy snapshot before encoding")
    func validatedSnapshot() {
        var policy = RunnerRuntimePolicy()
        policy.restartDelaySeconds = -1
        let config = RunnerLaunchConfiguration(runtimePolicy: policy, inheritHostPath: false, hostPath: "")
        #expect(config.runtimePolicy.restartDelaySeconds == 1)
    }
}
