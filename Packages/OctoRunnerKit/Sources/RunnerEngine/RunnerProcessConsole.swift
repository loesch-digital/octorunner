import Dispatch
import Foundation
import Synchronization

final class RunnerProcessConsole: Sendable {
    private struct State {
        var buffer = RunnerLogBuffer(maxLines: 200)
        var subscribers: [UUID: AsyncStream<RunnerLogSnapshot>.Continuation] = [:]
    }

    private let state = Mutex(State())

    func subscribe() -> AsyncStream<RunnerLogSnapshot> {
        let channel = AsyncStream<RunnerLogSnapshot>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        channel.continuation.onTermination = { [weak self] _ in
            // Delivery can also notice cancellation while the state is locked.
            Task { self?.unsubscribe(id) }
        }
        state.withLock {
            $0.subscribers[id] = channel.continuation
            channel.continuation.yield($0.buffer.snapshot)
        }
        return channel.stream
    }

    func record(_ output: RunnerLogByteFramer.Output, standardError: Bool) {
        guard !output.lines.isEmpty || output.discardedLineCount > 0 else { return }
        state.withLock {
            $0.buffer.append(output, standardError: standardError)
            let snapshot = $0.buffer.snapshot
            for continuation in $0.subscribers.values { continuation.yield(snapshot) }
        }
    }

    func finish() {
        let subscribers = state.withLock { state in
            let subscriptions = state.subscribers
            state.subscribers.removeAll()
            return subscriptions
        }
        for continuation in subscribers.values { continuation.finish() }
    }

    private func unsubscribe(_ id: UUID) {
        state.withLock { _ = $0.subscribers.removeValue(forKey: id) }
    }

    deinit { finish() }
}
