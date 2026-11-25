import CoreModels
import Foundation
import Observation
import RunnerEngine
import SwiftData
import SyncKit

/// Shared app lifetime services. Construction never requests system permissions.
@MainActor
public final class AppServices {
    public let preferences: AppPreferencesStore
    public let integration: AppIntegrationController
    public let backgroundMonitoring = BackgroundMonitoringController()
    public let notifications: AppNotificationsController
    public let historyRateBudget = WorkflowHistoryRateBudget()
    public let accounts = AccountSessionController()
    public let healthMonitor: RunnerHealthMonitor
    public let remoteSyncMonitor = RunnerRemoteSyncMonitor()
    public let storageMaintenance: StorageMaintenanceController
    public let diskMonitor: DiskSpaceMonitor
    public let jobFailureMonitor: LocalJobFailureMonitor
    public let supervisor: RunnerSupervisorActor
    public let launchAgents: RunnerLaunchAgentInspector
    private var powerMonitoring: Task<Void, Never>?
    private var recoveryMonitoring: Task<Void, Never>?
    private var recoveryNotificationDelivery: Task<Void, Never>?
    private var policyUpdate: Task<Void, Never>?

    public init(
        preferences: AppPreferencesStore = AppPreferencesStore(),
        loginService: (any LoginItemServicing)? = nil,
        notificationClient: any AppNotificationClient = SystemNotificationClient()
    ) {
        self.preferences = preferences
        let sampler = RunnerProcessSampler()
        supervisor = RunnerSupervisorActor(startCheck: { configuration in
            let name = RunnerServiceLabel.forRunner(named: configuration.name)
            guard try await LaunchAgentServiceStateReader().isUnloaded(label: name) else {
                throw RunnerSupervisionError.notManaged
            }
            let processes = try await sampler.sample()
            let root = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: configuration.rootDirectory)
            guard processes[root] == nil else { throw RunnerSupervisionError.notManaged }
        }, activitySample: { rootDirectory in
            let processes = try await sampler.sample()
            let root = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: rootDirectory)
            return (processes[root]?.listenerPID, processes[root]?.workerPID)
        }, recoveryPolicy: preferences.runtimePolicy,
            lowPowerMode: { ProcessInfo.processInfo.isLowPowerModeEnabled },
            maximumConcurrentRunners: preferences.maxConcurrentRunners)
        launchAgents = RunnerLaunchAgentInspector(supervisor: supervisor) { rootDirectory in
            let processes = try await sampler.sample()
            let root = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: rootDirectory)
            return processes[root] != nil
        }
        storageMaintenance = StorageMaintenanceController(preferences: preferences, supervisor: supervisor)
        integration = AppIntegrationController(preferences: preferences, loginService: loginService ?? supervisor)
        notifications = AppNotificationsController(preferences: preferences, client: notificationClient)
        healthMonitor = RunnerHealthMonitor(notifications: notifications, sampler: sampler, preferences: preferences,
            supervisor: supervisor, publishesRecoveryEvents: true)
        diskMonitor = DiskSpaceMonitor(preferences: preferences, notifications: notifications)
        jobFailureMonitor = LocalJobFailureMonitor(preferences: preferences, notifications: notifications, rateBudget: historyRateBudget)
    }

    public func startRecoveryMonitoring(container: ModelContainer) {
        guard recoveryMonitoring == nil else { return }
        observePolicy()
        powerMonitoring = Task { [supervisor] in
            let changes = NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange).map { _ in () }
            await supervisor.powerStateChanged()
            for await _ in changes {
                guard !Task.isCancelled else { return }
                await supervisor.powerStateChanged()
            }
        }
        let delivery = AsyncStream<AppNotificationEvent>.makeStream(bufferingPolicy: .bufferingNewest(128))
        recoveryNotificationDelivery = Task { [notifications] in
            for await event in delivery.stream {
                guard !Task.isCancelled else { return }
                await notifications.publish(event)
            }
        }
        recoveryMonitoring = Task { [supervisor, preferences] in
            defer { delivery.continuation.finish() }
            for await event in await supervisor.recoveryEvents() {
                guard !Task.isCancelled else { return }
                let locale = preferences.language.locale
                let title = AppLocalization.string(event.kind == .quarantine ? "Runner quarantined" : "Runner error", locale: locale)
                let summary = event.exitStatus.map { AppLocalization.string("Runner exit status: \(String($0))", locale: locale) }
                    ?? AppLocalization.string("The runner could not start.", locale: locale)
                AuditLogRecorder.record(in: container.mainContext, category: .runnerLifecycle,
                    severity: .critical, title: title, summary: "\(event.runnerName) (\(event.runnerID)): \(summary)",
                    targetRunnerName: event.runnerName)
                if event.shouldNotify {
                    delivery.continuation.yield(.init(id: "runner-recovery-\(event.runnerID)-\(event.generation)",
                        kind: .runnerError, title: title, message: event.runnerName))
                }
            }
        }
    }

    public func stopRecoveryMonitoring() {
        powerMonitoring?.cancel()
        recoveryMonitoring?.cancel()
        recoveryNotificationDelivery?.cancel()
        policyUpdate?.cancel()
    }

    private func observePolicy() {
        let (policy, maximum) = withObservationTracking {
            (preferences.runtimePolicy, preferences.maxConcurrentRunners)
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, self.recoveryMonitoring?.isCancelled == false else { return }
                self.observePolicy()
            }
        }
        policyUpdate?.cancel()
        policyUpdate = Task { [supervisor] in
            await supervisor.updateRecoveryPolicy(policy, maximumConcurrentRunners: maximum)
        }
    }
}
