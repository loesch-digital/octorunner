import Foundation
import Synchronization

enum PythonTestServerError: Error {
    case missingPort
}

/// An owned loopback fixture. Neither startup nor teardown blocks a cooperative
/// executor in FileHandle.availableData or Process.waitUntilExit().
func withPythonTestServer(
    script: String,
    body: (URL) async throws -> Void
) async throws {
    try Task.checkCancellation()
    let server = Process()
    let output = Pipe()
    let exit = TestServerExit()
    let (chunks, continuation) = AsyncStream.makeStream(of: Data.self)
    output.fileHandleForReading.readabilityHandler = { handle in
        let data = handle.availableData
        if data.isEmpty { continuation.finish() } else { continuation.yield(data) }
    }
    server.executableURL = URL(filePath: "/usr/bin/python3")
    // A fixture deadline also bounds startup if the script never announces a port.
    server.arguments = ["-u", "-c", """
    import os, threading
    _deadline = threading.Timer(30, lambda: os._exit(124))
    _deadline.daemon = True
    _deadline.start()
    \(script)
    """]
    server.standardOutput = output
    server.standardError = FileHandle.nullDevice
    server.terminationHandler = { _ in exit.finish() }
    defer {
        output.fileHandleForReading.readabilityHandler = nil
        continuation.finish()
        try? output.fileHandleForReading.close()
        try? output.fileHandleForWriting.close()
        server.terminationHandler = nil
    }
    try server.run()
    // Foundation closes the parent pipe writer on successful launch.
    let result: Result<Void, any Error>
    do {
        try await withTaskCancellationHandler {
            var data = Data()
            for await chunk in chunks {
                data.append(chunk)
                if data.contains(10) { break }
            }
            try Task.checkCancellation()
            guard let text = String(data: data, encoding: .utf8),
                  let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65535).contains(port),
                  let url = URL(string: "http://127.0.0.1:\(port)") else {
                throw PythonTestServerError.missingPort
            }
            try await body(url)
        } onCancel: {
            server.terminate()
        }
        result = .success(())
    } catch {
        result = .failure(error)
    }
    if server.isRunning { server.terminate() }
    // Deliberately finish owned-process cleanup even when the caller is cancelled.
    // The handler was installed before launch and remembers an already exited child.
    await exit.wait()
    try result.get()
}

private final class TestServerExit: Sendable {
    private struct State {
        var finished = false
        var waiter: CheckedContinuation<Void, Never>?
    }
    private let state = Mutex(State())

    func finish() {
        let waiter = state.withLock { state in
            state.finished = true
            let waiter = state.waiter
            state.waiter = nil
            return waiter
        }
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let finished = state.withLock { state in
                if state.finished { return true }
                state.waiter = continuation
                return false
            }
            if finished { continuation.resume() }
        }
    }
}
