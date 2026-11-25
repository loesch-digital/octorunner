import BackgroundMonitoringKit
import Foundation
import OSLog

@main
struct BackgroundMonitorAgent {
    private static let logger = Logger(subsystem: "io.octorunner.macos", category: "BackgroundMonitor")

    static func main() async throws {
        guard CommandLine.arguments.count == 2,
              let path = CommandLine.arguments.last,
              path.hasPrefix("/")
        else {
            logger.error("Missing monitoring configuration directory")
            return
        }
        let directory = URL(filePath: path, directoryHint: .isDirectory)
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
}
