import CoreModels
import Foundation
import RunnerEngine
import SwiftData
import SyncKit

@MainActor
enum RunnerMigrationCompletion {
    static func matchesPath(_ saved: String?, _ url: URL) -> Bool {
        guard let saved, !saved.isEmpty else { return false }
        return LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(filePath: saved))
            == LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: url)
    }

    /// Re-fetch after the engine await; a removed or changed runner must not be overwritten.
    static func apply(runnerID: UUID, expectedSourcePath: String, managedRoot: URL,
                      context: ModelContext, actorLogin: String?, launchAgentInstalled: Bool = true,
                      oldRemoteID: Int64? = nil, newRemoteID: Int64? = nil,
                      installedVersion: String? = nil, verifiedGroup: RunnerMigrationGroup? = nil) throws -> String? {
        try Task.checkCancellation()
        let descriptor = FetchDescriptor<RunnerEntity>(predicate: #Predicate { $0.id == runnerID })
        guard let runner = try context.fetch(descriptor).first,
              runner.isImportedLocal,
              oldRemoteID == nil || runner.githubRunnerId == oldRemoteID,
              matchesPath(runner.rootDirectoryPath ?? runner.workDirectoryPath, URL(filePath: expectedSourcePath)) else { return nil }
        let previousPath = runner.rootDirectoryPath
        let destination = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: managedRoot)
        try context.transaction {
            runner.rootDirectoryPath = destination
            runner.migratedSourcePath = expectedSourcePath
            runner.migratedSourceRemoteID = oldRemoteID
            runner.workDirectoryPath = managedRoot.appending(path: "_work").path(percentEncoded: false)
            runner.isImportedLocal = false
            runner.serviceLabel = RunnerServiceLabel.forRunner(named: runner.name)
            runner.executionMode = launchAgentInstalled ? .launchAgent : .direct
            runner.lastHeartbeat = .now
            runner.status = .offline
            runner.pid = nil
            runner.currentJobName = nil
            runner.currentRepo = nil
            if let newRemoteID { runner.githubRunnerId = newRemoteID }
            if let installedVersion { runner.runnerVersion = installedVersion }
            if let verifiedGroup {
                runner.githubRunnerGroupID = Int64(verifiedGroup.id)
                runner.githubRunnerGroupName = verifiedGroup.name
            }
            context.insert(AuditLogEntity(
                category: .configuration, severity: .info,
                title: "Runner Migrated into OctoRunner",
                summary: "Migrated \(runner.name) into \(destination)",
                actorAccountLogin: actorLogin, targetRunnerName: runner.name,
                previousValue: previousPath, newValue: destination
            ))
        }
        return runner.name
    }
}
