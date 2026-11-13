import Foundation
@testable import RunnerEngine
import Testing

struct ConfigurationProcessRunnerTests {
    @Test("Asynchronous process execution preserves successful and unsuccessful exit codes", arguments: [Int32(0), 7])
    func exitCode(_ code: Int32) async throws {
        let process = command("exit \(code)")
        #expect(try await ConfigurationProcessRunner.run(process) == code)
        #expect(!process.isRunning)
    }

    @Test("A launch failure completes with an error rather than leaving an unresolved continuation")
    func launchFailure() async {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/nonexistent-octorunner-test-\(UUID().uuidString)")
        await #expect(throws: (any Error).self) {
            try await ConfigurationProcessRunner.run(process)
        }
    }

    @Test("Cancellation after launch terminates and reaps the configuration process")
    func cancellationAfterLaunch() async throws {
        let readiness = Pipe()
        let input = Pipe()
        let started = AsyncStream<Void>.makeStream()
        readiness.fileHandleForReading.readabilityHandler = { handle in
            if !handle.availableData.isEmpty {
                started.continuation.yield(())
                started.continuation.finish()
            }
        }
        defer {
            readiness.fileHandleForReading.readabilityHandler = nil
            started.continuation.finish()
        }
        // cat remains blocked on the open stdin pipe. The readiness byte is an
        // actual process signal, so cancellation needs no arbitrary delay.
        let process = command("printf ready; exec /bin/cat")
        process.standardInput = input
        process.standardOutput = readiness
        let task = Task {
            defer { started.continuation.finish() }
            return try await ConfigurationProcessRunner.run(process)
        }
        for await _ in started.stream { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!process.isRunning)
    }

    private func command(_ script: String) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", script]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        return process
    }
}
