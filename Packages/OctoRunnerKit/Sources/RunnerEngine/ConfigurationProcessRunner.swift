import Foundation
import Synchronization

/// Owns an already configured, single-use setup process until it has exited.
/// Callers must not launch or mutate the process while this operation is running.
enum ConfigurationProcessRunner {
    static func run(_ process: Process) async throws -> Int32 {
        let operation = ConfigurationProcessOperation(process: process)
        let status = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                operation.start(continuation)
            }
        } onCancel: {
            operation.cancel()
        }
        try Task.checkCancellation()
        return status
    }
}

private final class ConfigurationProcessOperation: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Int32, any Error>?
        var started = false
        var finished = false
        var cancelled = false
    }

    private let process: Process
    private let state = Mutex(State())

    init(process: Process) {
        self.process = process
    }

    func start(_ continuation: CheckedContinuation<Int32, any Error>) {
        let immediateFailure: (any Error)? = state.withLock { state in
            guard !state.cancelled else { return CancellationError() }
            state.continuation = continuation
            process.terminationHandler = { [self] process in
                finish(status: process.terminationStatus)
            }
            do {
                // Serialize launch with cancellation: terminate() must never be
                // sent to an unlaunched Process (Foundation raises an exception).
                try process.run()
                state.started = true
                return nil
            } catch {
                state.finished = true
                state.continuation = nil
                process.terminationHandler = nil
                return error
            }
        }
        if let immediateFailure {
            continuation.resume(throwing: immediateFailure)
        }
    }

    func cancel() {
        state.withLock { state in
            state.cancelled = true
            if state.started && !state.finished {
                // Foundation handles the race with an already exited process.
                // SIGTERM requests cancellation; completion still waits for exit.
                process.terminate()
            }
        }
    }

    private func finish(status: Int32) {
        let completion = state.withLock { state -> (CheckedContinuation<Int32, any Error>, Bool)? in
            guard !state.finished, let continuation = state.continuation else { return nil }
            state.finished = true
            state.continuation = nil
            process.terminationHandler = nil
            return (continuation, state.cancelled)
        }
        guard let (continuation, cancelled) = completion else { return }
        if cancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            continuation.resume(returning: status)
        }
    }
}
