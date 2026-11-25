import BackgroundMonitoringKit
import CoreModels
import Foundation
import SwiftData
import SyncKit

@MainActor
public enum MonitoringConfigurationExporter {
    public static func configuration(
        in context: ModelContext,
        previous: MonitoringConfiguration? = nil
    ) throws -> MonitoringConfiguration {
        let registrations = try context.fetch(FetchDescriptor<RunnerEntity>())
        let runners = registrations.map { runner in
            MonitoringRunnerDescriptor(
                id: runner.id,
                name: runner.name,
                processRootPath: runner.rootDirectoryPath.flatMap { path in
                    guard path.hasPrefix("/") else { return nil }
                    return LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(fileURLWithPath: path))
                }
            )
        }.sorted { $0.id.uuidString < $1.id.uuidString }

        if let previous, previous.runners == runners { return previous }
        return MonitoringConfiguration(runners: runners)
    }
}
