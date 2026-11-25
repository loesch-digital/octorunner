import CoreModels
import Foundation
import SwiftData
import SyncKit

@MainActor
enum LocalRunnerImportStore {
    @discardableResult
    static func upsert(
        _ discoveredList: [DiscoveredLocalRunner],
        into modelContext: ModelContext,
        excludingPaths: Set<String> = []
    ) -> Int {
        guard var existingRunners = try? modelContext.fetch(FetchDescriptor<RunnerEntity>()) else { return 0 }
        var importedOrUpdated = 0

        for item in discoveredList {
            let path = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: item.rootDirectory)
            guard !excludingPaths.contains(path) else { continue }
            let isPreviousInstallation = existingRunners.contains { runner in
                guard let original = runner.migratedSourcePath, runner.migratedSourceRemoteID == item.config.agentId else {
                    return false
                }
                return LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(filePath: original)) == path
                    && URL(string: runner.scopeUrlString)?.path.lowercased() == item.config.gitHubUrl.path.lowercased()
            }
            guard !isPreviousInstallation else { continue }
            let pathMatch = existingRunners.first { runner in
                guard let root = runner.rootDirectoryPath else { return false }
                return LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(filePath: root)) == path
            }
            func sameScope(_ runner: RunnerEntity) -> Bool {
                let recorded = URL(string: runner.scopeUrlString)
                let discovered = item.config.gitHubUrl
                return recorded?.scheme?.lowercased() == discovered.scheme?.lowercased()
                    && recorded?.host?.lowercased() == discovered.host?.lowercased()
                    && recorded?.port == discovered.port
                    && recorded?.path.lowercased() == discovered.path.lowercased()
            }
            if let pathMatch {
                guard sameScope(pathMatch),
                      pathMatch.githubRunnerId == nil || pathMatch.githubRunnerId == item.config.agentId else { continue }
            }
            let legacyMatch = existingRunners.first { runner in
                guard runner.executionMode != .direct, runner.executionMode != .launchAgent else { return false }
                return runner.githubRunnerId == item.config.agentId && sameScope(runner)
            }
            if let existing = pathMatch ?? legacyMatch {
                existing.githubRunnerId = item.config.agentId
                existing.name = item.config.agentName
                existing.scopeType = item.config.inferredScopeType
                existing.scopeUrlString = item.config.gitHubUrl.absoluteString
                if existing.githubRunnerGroupID == nil, existing.scopeType == .organization {
                    existing.githubRunnerGroupID = item.config.poolId.map(Int64.init)
                    existing.githubRunnerGroupName = item.config.poolName
                }
                existing.workDirectoryPath = item.workDirectory.path(percentEncoded: false)
                existing.rootDirectoryPath = item.rootDirectory.path(percentEncoded: false)
                existing.runnerVersion = item.runnerVersion
                existing.pid = item.listenerPID
                existing.status = item.localStatus
                existing.lastHeartbeat = .now
            } else {
                let entity = RunnerEntity(
                    name: item.config.agentName,
                    scopeType: item.config.inferredScopeType,
                    scopeUrl: item.config.gitHubUrl,
                    status: item.localStatus,
                    labels: item.labels,
                    workDirectory: item.workDirectory,
                    rootDirectoryPath: item.rootDirectory.path(percentEncoded: false),
                    runnerVersion: item.runnerVersion,
                    isImportedLocal: true,
                    pid: item.listenerPID
                )
                entity.githubRunnerId = item.config.agentId
                if entity.scopeType == .organization {
                    entity.githubRunnerGroupID = item.config.poolId.map(Int64.init)
                    entity.githubRunnerGroupName = item.config.poolName
                }
                modelContext.insert(entity)
                existingRunners.append(entity)

                AuditLogRecorder.record(
                    in: modelContext,
                    category: .runnerLifecycle,
                    severity: .info,
                    title: "Local Runner Auto-Imported",
                    summary: "Imported \(item.config.agentName) (agentId \(item.config.agentId), \(item.config.gitHubUrl.absoluteString))",
                    targetRunnerName: item.config.agentName,
                    newValue: item.labels.joined(separator: ",")
                )
            }
            importedOrUpdated += 1
        }

        try? modelContext.save()
        return importedOrUpdated
    }
}
