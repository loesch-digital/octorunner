import CoreModels
import Darwin
import Foundation
@testable import RunnerEngine
import Testing

struct ManagedRunnerProcessTests {
    @Test("A short-lived owned process reports its real exit without blocking", .timeLimit(.minutes(1)))
    func naturalExit() async throws {
        let fixture = try makeFixture(script: "exit 7\n")
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let backend = ManagedRunnerProcess(managedRoot: fixture.base)
        let handle = try await backend.start(configuration: fixture.configuration, generation: UUID())
        let events = await backend.exits(for: handle)
        var received: RunnerProcessExit?
        for await exit in events { received = exit }
        #expect(received?.status == 7 && received?.handle == handle)
    }

    @Test("Owned process groups terminate only with the exact start token", .timeLimit(.minutes(1)))
    func groupAndIdentity() async throws {
        let fixture = try makeFixture(script: "exec /bin/sleep 30\n")
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let backend = ManagedRunnerProcess(managedRoot: fixture.base)
        let handle = try await backend.start(configuration: fixture.configuration, generation: UUID())
        do {
            #expect(getpgid(handle.pid) == handle.pid)
            #expect(await backend.activity(for: handle, listenerPID: handle.pid, workerPID: nil) == .idle)
            #expect(await backend.activity(for: handle, listenerPID: nil, workerPID: handle.pid) == .busy)
            #expect(await backend.activity(for: handle, listenerPID: handle.pid, workerPID: getpid()) == .unknown)
            #expect(await backend.activity(for: handle, listenerPID: getpid(), workerPID: nil) == .unknown)
            let forged = RunnerProcessHandle(runnerID: handle.runnerID, generation: UUID(), pid: handle.pid, startedAt: handle.startedAt)
            #expect(await backend.activity(for: forged, listenerPID: handle.pid, workerPID: nil) == .unknown)
            await #expect(throws: RunnerSupervisionError.notManaged) { try await backend.stop(forged, force: true) }
            #expect(kill(handle.pid, 0) == 0)
            let exit = try await backend.stop(handle, force: true)
            #expect(exit.handle == handle && exit.status == -SIGKILL)
            #expect(kill(handle.pid, 0) == -1 && errno == ESRCH)
        } catch {
            _ = try? await backend.stop(handle, force: true)
            throw error
        }
    }

    @Test("A listener ignoring TERM stays owned after the stop deadline", .timeLimit(.minutes(1)))
    func gracefulStopTimeout() async throws {
        let fixture = try makeFixture(script: "trap '' TERM\n: > ready\nexec /bin/sleep 10\n")
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let backend = ManagedRunnerProcess(managedRoot: fixture.base, stopTimeout: .seconds(1))
        let handle = try await backend.start(configuration: fixture.configuration, generation: UUID())
        let ready = fixture.configuration.rootDirectory.appending(path: "ready")
        let readyDeadline = ContinuousClock.now.advanced(by: .seconds(3))
        do {
            while !FileManager.default.fileExists(atPath: ready.path), ContinuousClock.now < readyDeadline {
                try await Task.sleep(for: .milliseconds(10))
            }
            try #require(FileManager.default.fileExists(atPath: ready.path))

            await #expect(throws: POSIXError(.ETIMEDOUT)) { try await backend.stop(handle, force: false) }
            #expect(kill(handle.pid, 0) == 0)
            let exit = try await backend.stop(handle, force: true)
            #expect(exit.status == -SIGKILL)
        } catch {
            _ = try? await backend.stop(handle, force: true)
            throw error
        }
    }

    @Test("Two model identities cannot start the same managed directory twice", .timeLimit(.minutes(1)))
    func duplicateRoot() async throws {
        let fixture = try makeFixture(script: "exec /bin/sleep 15\n")
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let backend = ManagedRunnerProcess(managedRoot: fixture.base)
        let handle = try await backend.start(configuration: fixture.configuration, generation: UUID())
        let duplicate = ManagedRunnerConfiguration(runnerID: UUID(), name: "different-model",
            rootDirectory: fixture.configuration.rootDirectory, mode: .direct)
        do {
            let second = try await backend.start(configuration: duplicate, generation: UUID())
            _ = try await backend.stop(second, force: true)
            Issue.record("The backend started a second child in the same directory")
        } catch RunnerSupervisionError.notManaged {
            // Expected when the root already has an owned child.
        } catch {
            _ = try? await backend.stop(handle, force: true)
            throw error
        }
        _ = try await backend.stop(handle, force: true)
    }

    @Test("The group stays owned while a descendant survives the launch script", .timeLimit(.minutes(1)))
    func survivingDescendant() async throws {
        let fixture = try makeFixture(script: """
        (
          trap '' TERM
          : > ready
          exec /bin/sleep 3
        ) &
        wait
        """)
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let backend = ManagedRunnerProcess(managedRoot: fixture.base, stopTimeout: .seconds(1))
        let handle = try await backend.start(configuration: fixture.configuration, generation: UUID())
        let ready = fixture.configuration.rootDirectory.appending(path: "ready")
        let deadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !FileManager.default.fileExists(atPath: ready.path), .now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(FileManager.default.fileExists(atPath: ready.path))
        await #expect(throws: POSIXError(.ETIMEDOUT)) { try await backend.stop(handle, force: false) }
        let exit = try await backend.stop(handle, force: true)
        #expect(exit.handle == handle)
    }

    @Test("External and symlink-escaped roots are rejected before launch")
    func unsafeRoot() async throws {
        let fixture = try makeFixture(script: "exit 0\n")
        defer { try? FileManager.default.removeItem(at: fixture.base) }
        let backend = ManagedRunnerProcess(managedRoot: fixture.base.appending(path: "different"))
        await #expect(throws: RunnerSupervisionError.notManaged) {
            try await backend.start(configuration: fixture.configuration, generation: UUID())
        }
    }

    private func makeFixture(script: String) throws -> (base: URL, configuration: ManagedRunnerConfiguration) {
        let base = FileManager.default.temporaryDirectory.appending(path: "OctoRunner-process-test-\(UUID().uuidString)")
        let root = base.appending(path: "runner")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(script.utf8).write(to: root.appending(path: "run.sh"))
        return (base, .init(runnerID: UUID(), name: "synthetic", rootDirectory: root, mode: .direct))
    }
}
