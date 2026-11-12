import Foundation
@testable import RunnerEngine
import Testing

struct LaunchAgentRegistrationTests {
    @Test("A nonzero launchctl exit is never reported as successful registration")
    func rejectedRegistration() async throws {
        let fixture = try RegistrationFixture(body: "printf 'synthetic-private-registration-detail' >&2\nexit 7")
        defer { fixture.remove() }
        do {
            _ = try await RunnerProvisionerActor.bootstrapLaunchAgent(plistURL: fixture.plist, executableURL: fixture.executable)
            Issue.record("A rejected registration was accepted")
        } catch let RunnerEngineError.launchAgentRegistrationFailed(status, detail) {
            #expect(status == 7)
            #expect(!detail.contains("synthetic-private-registration-detail"))
            #expect(!detail.contains(fixture.plist.path(percentEncoded: false)))
        }
    }

    @Test("Bootstrap receives native plist paths with spaces as one argument")
    func nativeArguments() async throws {
        let fixture = try RegistrationFixture(body: "printf '%s\\n' \"$@\" > \"$(dirname \"$0\")/arguments.txt\"\nexit 0")
        defer { fixture.remove() }
        _ = try await RunnerProvisionerActor.bootstrapLaunchAgent(plistURL: fixture.plist, executableURL: fixture.executable)
        let arguments = try String(contentsOf: fixture.root.appending(path: "arguments.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init)
        #expect(arguments == ["bootstrap", "gui/\(getuid())", fixture.plist.path(percentEncoded: false)])
    }

    @Test("Pre-cancelled registration starts no launchctl process")
    func cancelledBeforeLaunch() async throws {
        let fixture = try RegistrationFixture(body: "printf launched > \"$(dirname \"$0\")/launched.txt\"\nexit 0")
        defer { fixture.remove() }
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RunnerProvisionerActor.bootstrapLaunchAgent(plistURL: fixture.plist, executableURL: fixture.executable)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!FileManager.default.fileExists(atPath: fixture.root.appending(path: "launched.txt").path(percentEncoded: false)))
    }
}

private struct RegistrationFixture {
    let root: URL
    let executable: URL
    let plist: URL

    init(body: String) throws {
        root = FileManager.default.temporaryDirectory.appending(path: "registration fixture \(UUID())")
        executable = root.appending(path: "fixture-launchctl")
        plist = root.appending(path: "runner config 100%.plist")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ("#!/bin/bash\n" + body + "\n").write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path(percentEncoded: false))
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
}
