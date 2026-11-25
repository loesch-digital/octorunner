import CoreModels
import Foundation
import RunnerEngine
import SwiftData

@MainActor
enum RunnerWizardProvisioning {
    static func persistProvisionedRunners(_ summaries: [ProvisionedRunnerSummary], in context: ModelContext,
        accountLogin login: String, launchAgent: Bool, configuration: RunnerLaunchConfiguration
    ) throws -> (directRunners: [ManagedRunnerConfiguration], startFailures: [String], serviceInstallFailures: [String]) {
        var directRunners: [ManagedRunnerConfiguration] = []
        var startFailures: [String] = []
        var serviceInstallFailures: [String] = []
        try context.transaction {
            for summary in summaries {
                let id = UUID()
                let mode: RunnerExecutionMode = summary.launchdLabel == nil ? .direct : .launchAgent
                let entity = RunnerEntity(
                    id: id,
                    name: summary.name,
                    scopeType: summary.scopeType,
                    scopeUrl: summary.scopeURL,
                    status: .offline,
                    labels: summary.labels,
                    workDirectory: summary.workDirectory,
                    rootDirectoryPath: summary.rootDirectory.path(percentEncoded: false),
                    runnerVersion: summary.runnerVersion,
                    pid: summary.pid,
                    executionMode: mode
                )
                entity.githubRunnerId = summary.remoteID
                entity.githubRunnerGroupID = summary.remoteGroupID
                entity.githubRunnerGroupName = summary.remoteGroupName
                if let label = summary.launchdLabel {
                    entity.serviceLabel = label
                }
                context.insert(entity)
                context.insert(AuditLogEntity(
                    category: .runnerLifecycle,
                    title: "Runner Provisioned",
                    summary: "Provisioned \(summary.name) (\(summary.scopeURL.absoluteString), v\(summary.runnerVersion))",
                    actorAccountLogin: login,
                    targetRunnerName: summary.name,
                    newValue: summary.labels.joined(separator: ",")
                ))
                if launchAgent && (summary.launchAgentFailed || summary.launchdLabel == nil) {
                    if mode == .direct {
                        serviceInstallFailures.append(summary.name)
                    } else {
                        startFailures.append(summary.name)
                    }
                    context.insert(AuditLogEntity(
                        category: .runnerLifecycle, severity: .warning, title: "Runner Start Failed",
                        summary: "Could not start \(summary.name) (\(id.uuidString)).",
                        actorAccountLogin: login, targetRunnerName: summary.name
                    ))
                } else if mode == .direct {
                    directRunners.append(.init(runnerID: id, name: summary.name, rootDirectory: summary.rootDirectory,
                        mode: .direct, launch: configuration))
                }
            }
        }
        return (directRunners, startFailures, serviceInstallFailures)
    }

    static func startDirectRunners(_ directRunners: [ManagedRunnerConfiguration], in context: ModelContext,
        accountLogin login: String, supervisor: RunnerSupervisorActor
    ) async throws -> [String] {
        var startFailures: [String] = []
        for runner in directRunners {
            try Task.checkCancellation()
            do {
                try await supervisor.configure(runner)
                try await supervisor.start(runnerID: runner.runnerID)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try Task.checkCancellation()
                startFailures.append(runner.name)
                AuditLogRecorder.record(
                    in: context,
                    category: .runnerLifecycle,
                    severity: .warning,
                    title: "Runner Start Failed",
                    summary: "Could not start \(runner.name) (\(runner.runnerID.uuidString)).",
                    actorAccountLogin: login,
                    targetRunnerName: runner.name
                )
            }
        }
        return startFailures
    }
}
