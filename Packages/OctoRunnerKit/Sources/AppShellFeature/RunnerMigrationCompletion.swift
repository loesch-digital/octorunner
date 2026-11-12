import CoreModels
import Foundation
import SwiftData

@MainActor
enum RunnerMigrationCompletion {
    /// Re-fetch after the engine await; a removed or changed runner must not be overwritten.
    static func apply(runnerID: UUID, expectedSourcePath: String, managedRoot: URL,
                      context: ModelContext, actorLogin: String?) throws -> String? {
        try Task.checkCancellation()
        let descriptor = FetchDescriptor<RunnerEntity>(predicate: #Predicate { $0.id == runnerID })
        guard let runner = try context.fetch(descriptor).first,
              runner.isImportedLocal,
              (runner.rootDirectoryPath ?? runner.workDirectoryPath) == expectedSourcePath else { return nil }
        let previousPath = runner.rootDirectoryPath
        runner.rootDirectoryPath = managedRoot.path(percentEncoded: false)
        runner.workDirectoryPath = managedRoot.appending(path: "_work").path(percentEncoded: false)
        runner.isImportedLocal = false
        runner.lastHeartbeat = .now
        AuditLogRecorder.record(
            in: context, category: .configuration, severity: .info,
            title: "Runner Migrated into OctoRunner",
            summary: "Migrated \(runner.name) into \(managedRoot.path(percentEncoded: false)) and enabled Autostart",
            actorAccountLogin: actorLogin, targetRunnerName: runner.name,
            previousValue: previousPath, newValue: managedRoot.path(percentEncoded: false)
        )
        try context.save()
        return runner.name
    }
}
