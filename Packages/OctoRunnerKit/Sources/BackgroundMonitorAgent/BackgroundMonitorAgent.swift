import BackgroundMonitoringKit
import Foundation
import OSLog

@main
struct BackgroundMonitorAgent {
    private static let logger = Logger(subsystem: "io.octorunner.macos", category: "BackgroundMonitor")

    static func main() async throws {
        let directory: URL
        switch CommandLine.arguments.dropFirst().first {
        case nil:
            directory = MonitoringStorage.directory
        case let path? where path.hasPrefix("/") && CommandLine.arguments.count == 2:
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
}
