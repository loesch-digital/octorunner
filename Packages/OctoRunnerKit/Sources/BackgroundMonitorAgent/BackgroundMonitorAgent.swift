import BackgroundMonitoringKit
import Foundation
import OSLog

@main
struct BackgroundMonitorAgent {
    private static let logger = Logger(subsystem: "io.octorunner.macos", category: "BackgroundMonitor")

    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.count == 2, arguments[0] == "--configuration-revision",
           let revision = UUID(uuidString: arguments[1]) {
            try await monitorAfterQuit(revision: revision)
            return
        }
        let directory: URL
        switch arguments.first {
        case nil:
            directory = MonitoringStorage.directory
        case let path? where path.hasPrefix("/") && arguments.count == 1:
            directory = URL(filePath: path, directoryHint: .isDirectory)
        default:
            logger.error("Invalid monitoring configuration directory")
            return
        }
        let store = MonitoringSnapshotStore(directory: directory)
        let monitor = LocalBackgroundMonitor(store: store)
        let lease = MonitoringLease(lockFile: directory.appending(path: "monitoring.lock"))

        while !Task.isCancelled {
            do {
                if try store.readConfiguration() != nil {
                    _ = try await lease.withOwnership { try await monitor.refresh() }
                }
            } catch is CancellationError {
                return
            } catch {
                logger.error("Unable to publish a local runner observation")
            }
            try await Task.sleep(for: .seconds(15))
        }
    }

    private static func monitorAfterQuit(revision: UUID) async throws {
        let directory = MonitoringStorage.directory
        let store = MonitoringSnapshotStore(directory: directory)
        let monitor = LocalBackgroundMonitor(store: store)
        let lifetime = MonitoringLease(lockFile: directory.appending(path: "worker.lock"))
        try await lifetime.withOwnership {
            while try store.readConfiguration()?.revision == revision {
                try await monitor.refresh(requiringRevision: revision)
                for _ in 0..<15 {
                    try await Task.sleep(for: .seconds(1))
                    if try store.readConfiguration()?.revision != revision { return }
                }
            }
        }
    }
}
