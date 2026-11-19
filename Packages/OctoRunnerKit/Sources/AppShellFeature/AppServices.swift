import CoreModels
import RunnerEngine
import SyncKit

/// Shared app lifetime services. Construction never requests system permissions.
@MainActor
public final class AppServices {
    public let preferences: AppPreferencesStore
    public let integration: AppIntegrationController
    public let notifications: AppNotificationsController
    public let historyRateBudget = WorkflowHistoryRateBudget()
    public let accounts = AccountSessionController()
    public let healthMonitor: RunnerHealthMonitor
    public let storageMaintenance: StorageMaintenanceController
    public let diskMonitor: DiskSpaceMonitor
    public let jobFailureMonitor: LocalJobFailureMonitor
    public let supervisor: RunnerSupervisorActor
    public let launchAgents: RunnerLaunchAgentInspector

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
        })
        launchAgents = RunnerLaunchAgentInspector(supervisor: supervisor) { rootDirectory in
            let processes = try await sampler.sample()
            let root = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: rootDirectory)
            return processes[root] != nil
        }
        storageMaintenance = StorageMaintenanceController(preferences: preferences, supervisor: supervisor)
        integration = AppIntegrationController(preferences: preferences, loginService: loginService ?? supervisor)
        notifications = AppNotificationsController(preferences: preferences, client: notificationClient)
        healthMonitor = RunnerHealthMonitor(notifications: notifications, sampler: sampler, preferences: preferences, supervisor: supervisor)
        diskMonitor = DiskSpaceMonitor(preferences: preferences, notifications: notifications)
        jobFailureMonitor = LocalJobFailureMonitor(preferences: preferences, notifications: notifications, rateBudget: historyRateBudget)
    }
}
