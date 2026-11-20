import CoreModels
import Foundation
@testable import RunnerEngine
import Testing

struct LaunchAgentDiagnosticsTests {
    @Test("Loading a LaunchAgent respects reservations held by process and storage operations")
    func directoryReservation() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        try fixture.writeDefinition()
        let supervisor = RunnerSupervisorActor()
        let reservation = await supervisor.reserveIdleDirectories(roots: [fixture.root])
        let command = LaunchctlFixture()
        let inspector = fixture.inspector(command, supervisor: supervisor)

        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await inspector.loadDefinition(fixture.target)
        }
        #expect(await command.commands.allSatisfy { $0[0] == "print" })
        await supervisor.releaseDirectories(paths: reservation)
        try await inspector.loadDefinition(fixture.target)
        #expect(await command.commands.last?.first == "bootstrap")
    }

    @Test("Loading a verified inactive LaunchAgent never replaces a loaded service")
    func loadInactiveDefinition() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        try fixture.writeDefinition()
        let command = LaunchctlFixture()
        let inspector = fixture.inspector(command)
        await command.set(status: 0, output: fixture.launchctlOutput(pid: Int32.max))
        await #expect(throws: RunnerSupervisionError.operationInProgress) {
            try await inspector.loadDefinition(fixture.target)
        }
        #expect(await command.commands.map { $0[0] } == ["print"])
        await command.set(status: 113, output: "")
        try await inspector.loadDefinition(fixture.target)
        let bootstrap = try #require(await command.commands.last)
        #expect(Array(bootstrap.prefix(2)) == ["bootstrap", "gui/\(getuid())"])
        #expect(bootstrap.last != fixture.plist.path)
        #expect(await command.loadedDefinition?.contains(fixture.target.label) == true)
        #expect(!FileManager.default.fileExists(atPath: try #require(bootstrap.last)))

        await command.set(status: 0, output: fixture.launchctlOutput(path: bootstrap.last, pid: nil))
        #expect(try await fixture.inspector(command).runtime(fixture.target) == .loaded)
    }

    @Test("A historical OctoRunner LaunchAgent remains verifiable")
    func legacyDefinition() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        let definition: [String: Any] = [
            "Label": fixture.target.label,
            "ProgramArguments": ["/bin/bash", fixture.root.appending(path: "run.sh").path],
            "WorkingDirectory": fixture.root.path,
            "RunAtLoad": true,
            "KeepAlive": true,
            "EnvironmentVariables": [
                "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
                "LANG": "en_US.UTF-8",
            ],
            "StandardOutPath": fixture.root.appending(path: "_diag/launchd.stdout.log").path,
            "StandardErrorPath": fixture.root.appending(path: "_diag/launchd.stderr.log").path,
        ]
        try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0)
            .write(to: fixture.plist)
        #expect(try await fixture.inspector.inspect(fixture.target).definition == .verified)
    }

    @Test("LaunchAgent startup accepts a generated directory-hinted path and historical trailing slashes")
    func directoryHintDefinition() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        let root = URL(filePath: fixture.root.path, directoryHint: .isDirectory)
        try fixture.writeDefinition(root: root)
        #expect(try await fixture.inspector.inspect(fixture.target).definition == .verified)
        let data = try Data(contentsOf: fixture.plist)
        let contents = try PropertyListSerialization.propertyList(from: data, format: nil)
        var definition = try #require(contents as? [String: Any])
        #expect(definition["WorkingDirectory"] as? String == fixture.root.path)
        definition["WorkingDirectory"] = fixture.root.path + "/"
        try PropertyListSerialization.data(fromPropertyList: definition, format: .xml, options: 0).write(to: fixture.plist)
        #expect(try await fixture.inspector.inspect(fixture.target).definition == .verified)
    }

    @Test("Bootstrap consumes the verified snapshot even if the installed plist is replaced")
    func bootstrapSnapshot() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        try fixture.writeDefinition()
        let command = LaunchctlFixture()
        await command.setBeforeBootstrap {
            try fixture.writeDefinition(root: fixture.base.appending(path: "different-root"))
        }
        try await fixture.inspector(command).loadDefinition(fixture.target)
        let definition = try #require(await command.loadedDefinition)
        #expect(definition.contains(fixture.root.appending(path: "run.sh").path))
        #expect(!definition.contains("different-root"))
    }

    @Test("Bootstrap does not follow a runner startup script outside the managed directory")
    func symlinkedStartupScript() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        try fixture.writeDefinition()
        let script = fixture.root.appending(path: "run.sh")
        try FileManager.default.removeItem(at: script)
        try FileManager.default.createSymbolicLink(at: script, withDestinationURL: fixture.base.appending(path: "outside.sh"))
        let command = LaunchctlFixture()
        await #expect(throws: RunnerSupervisionError.notManaged) {
            try await fixture.inspector(command).loadDefinition(fixture.target)
        }
        #expect(await command.commands.allSatisfy { $0[0] == "print" })
    }

    @Test("A definition replaced during verification is never loaded")
    func replacedDefinition() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        try fixture.writeDefinition()
        let command = LaunchctlFixture()
        let inspector = fixture.inspector(command, hasAnotherListener: { _ in
            try fixture.writeDefinition(root: fixture.base.appending(path: "another-root"))
            return false
        })
        await #expect(throws: RunnerSupervisionError.notManaged) {
            try await inspector.loadDefinition(fixture.target)
        }
        #expect(await command.commands.allSatisfy { $0[0] == "print" })
    }

    @Test("The installed plist does not stand in for live service identity")
    func runningServiceIdentity() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        try fixture.writeDefinition()
        let command = LaunchctlFixture()
        let inspector = fixture.inspector(command)

        await command.set(status: 113, output: "")
        #expect(try await inspector.runtime(fixture.target) == .unloaded)

        await command.set(status: 0, output: fixture.launchctlOutput(pid: Int32.max))
        #expect(try await inspector.runtime(fixture.target) == .running(pid: Int32.max, startedAt: nil))

        await command.set(status: 0, output: fixture.launchctlOutput(path: "/tmp/other.plist", pid: nil))
        #expect(try await inspector.runtime(fixture.target) == .unverified)
    }

    @Test("Shows the matching installed service definition as read-only XML")
    func verifiedDefinition() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        try fixture.writeDefinition()

        let result = try await fixture.inspector.inspect(fixture.target)
        #expect(result.definition == .verified)
        #expect(result.xml?.contains(fixture.target.label) == true)
        #expect(result.xml?.contains(fixture.root.appending(path: "run.sh").path) == true)
    }

    @Test("Missing, invalid, and unrelated definitions are distinguished")
    func missingAndMismatchedDefinition() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }

        let missing = try await fixture.inspector.inspect(fixture.target)
        #expect(missing.definition == .missing)
        #expect(missing.xml == nil)

        try Data("not a property list".utf8).write(to: fixture.plist)
        let invalid = try await fixture.inspector.inspect(fixture.target)
        #expect(invalid.definition == .invalid)
        #expect(invalid.xml == nil)

        try fixture.writeDefinition(root: fixture.base.appending(path: "other-runner"))
        let unrelated = try await fixture.inspector.inspect(fixture.target)
        #expect(unrelated.definition == .unverified)
        #expect(unrelated.xml == nil)
    }

    @Test("Symlink definitions and additional environment settings are kept out of diagnostics")
    func unsafeDefinition() async throws {
        let fixture = try LaunchAgentDiagnosticFixture()
        defer { fixture.remove() }
        let other = fixture.base.appending(path: "other.plist")
        let data = try LaunchAgentPlistGenerator.generatePlistData(serviceLabel: fixture.target.label, runnerRootDirectory: fixture.root)
        try data.write(to: other)
        try FileManager.default.createSymbolicLink(at: fixture.plist, withDestinationURL: other)
        let linked = try await fixture.inspector.inspect(fixture.target)
        #expect(linked.definition == .unverified)
        #expect(linked.xml == nil)

        try FileManager.default.removeItem(at: fixture.plist)
        var plist = try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
        plist["EnvironmentVariables"] = ["CUSTOM": "fixture-private-value"]
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: fixture.plist)
        let edited = try await fixture.inspector.inspect(fixture.target)
        #expect(edited.definition == .unverified)
        #expect(edited.xml == nil)
    }
}

private struct LaunchAgentDiagnosticFixture {
    let base: URL
    let root: URL
    let agents: URL
    let plist: URL
    let target: RunnerLaunchAgentTarget

    init() throws {
        base = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appending(path: "OctoRunner-launchd-\(UUID())")
        let managed = base.appending(path: "managed")
        root = managed.appending(path: "Build Runner")
        agents = base.appending(path: "agents")
        target = .init(name: "Build Runner", rootDirectory: root, label: RunnerServiceLabel.forRunner(named: "Build Runner"))
        plist = agents.appending(path: target.label + ".plist")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appending(path: "_diag"), withIntermediateDirectories: false)
        try Data("#!/bin/bash\nexit 0\n".utf8).write(to: root.appending(path: "run.sh"))
        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
    }

    var inspector: RunnerLaunchAgentInspector {
        .init(managedRoot: root.deletingLastPathComponent(), launchAgentsDirectory: agents)
    }

    func inspector(_ command: LaunchctlFixture, supervisor: RunnerSupervisorActor = RunnerSupervisorActor(),
                   hasAnotherListener: @escaping @Sendable (URL) async throws -> Bool = { _ in false }) -> RunnerLaunchAgentInspector {
        .init(managedRoot: root.deletingLastPathComponent(), launchAgentsDirectory: agents,
            launchctl: { try await command.run($0) }, supervisor: supervisor, hasAnotherListener: hasAnotherListener)
    }

    func launchctlOutput(path: String? = nil, pid: Int32?) -> String {
        [
            "gui/\(getuid())/\(target.label) = {",
            "\tpath = \(path ?? plist.path)",
            "\ttype = LaunchAgent",
            "\tstate = \(pid == nil ? "not running" : "running")",
            "\tprogram = /bin/bash",
            "\tworking directory = \(root.path)",
            "\targuments = {",
            "\t\t/bin/bash",
            "\t\t\(root.appending(path: "run.sh").path)",
            "\t}",
            pid.map { "\tpid = \($0)" } ?? "",
            "}"
        ].joined(separator: "\n")
    }

    func writeDefinition(root override: URL? = nil) throws {
        try LaunchAgentPlistGenerator.generatePlistData(serviceLabel: target.label, runnerRootDirectory: override ?? root)
            .write(to: plist)
    }

    func remove() { try? FileManager.default.removeItem(at: base) }
}

private actor LaunchctlFixture {
    private var response = (status: Int32(113), output: "")
    private var beforeBootstrap: (@Sendable () throws -> Void)?
    private(set) var commands: [[String]] = []
    private(set) var loadedDefinition: String?

    func set(status: Int32, output: String) {
        response = (status, output)
    }

    func setBeforeBootstrap(_ action: @escaping @Sendable () throws -> Void) {
        beforeBootstrap = action
    }

    func run(_ arguments: [String]) async throws -> (status: Int32, output: String) {
        commands.append(arguments)
        if arguments.first == "bootstrap" {
            try beforeBootstrap?()
            loadedDefinition = try String(contentsOfFile: arguments[2], encoding: .utf8)
            return (0, "")
        }
        return response
    }
}
