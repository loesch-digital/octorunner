import Darwin
import Foundation
import Testing

struct TestServerLifecycleTests {
    @Test("Server cleanup awaits actual exit, including a server exiting before cleanup", .timeLimit(.minutes(1)))
    func fastExit() async throws {
        for _ in 0..<20 {
            try await withPythonTestServer(script: "print(12345, flush=True)") { url in
                #expect(url.port == 12345)
            }
        }
    }

    @Test("Server failure before announcing a port fails instead of blocking", .timeLimit(.minutes(1)))
    func startupFailure() async {
        await #expect(throws: PythonTestServerError.self) {
            try await withPythonTestServer(script: "raise SystemExit(1)") { _ in
                Issue.record("Failed server must not reach the test body")
            }
        }
    }

    @Test("Throwing from a server test still awaits server cleanup", .timeLimit(.minutes(1)))
    func throwingBody() async throws {
        try await assertServerExited { script in
            await #expect(throws: CancellationError.self) {
                try await withPythonTestServer(script: script) { _ in
                    throw CancellationError()
                }
            }
        }
    }

    @Test("Cancellation stops the owned server and propagates to its caller", .timeLimit(.minutes(1)))
    func cancellation() async throws {
        try await assertServerExited { script in
            let (ready, signal) = AsyncStream.makeStream(of: Void.self)
            let task = Task {
                defer { signal.finish() }
                try await withPythonTestServer(script: script) { _ in
                    signal.yield(())
                    try await Task.sleep(for: .seconds(30))
                }
            }
            for await _ in ready { break }
            task.cancel()
            await #expect(throws: CancellationError.self) { try await task.value }
        }
    }

    private func assertServerExited(_ operation: (String) async throws -> Void) async throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "test-server-\(UUID().uuidString).pid")
        defer { try? FileManager.default.removeItem(at: file) }
        let script = """
        import os, signal, time
        def stop(*args):
            time.sleep(0.1)
            os._exit(0)
        signal.signal(signal.SIGTERM, stop)
        with open(\(String(reflecting: file.path)), "w") as pidfile:
            pidfile.write(str(os.getpid()))
        print(12345, flush=True)
        while True:
            time.sleep(1)
        """
        try await operation(script)
        let pid = try #require(Int32(String(contentsOf: file, encoding: .utf8)))
        let result = kill(pid, 0)
        let error = errno
        #expect(result == -1 && error == ESRCH, "Owned server must have exited before cleanup returns")
    }
}
