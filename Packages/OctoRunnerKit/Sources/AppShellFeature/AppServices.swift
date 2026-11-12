import CoreModels
import RunnerEngine

/// Shared app lifetime services. Construction never requests system permissions.
@MainActor
public final class AppServices {
    public let preferences: AppPreferencesStore
    public let integration: AppIntegrationController
    public let notifications: AppNotificationsController
    public let historyRateBudget = WorkflowHistoryRateBudget()
    public let accounts = AccountSessionController()
    public let healthMonitor: RunnerHealthMonitor
    public let diskMonitor: DiskSpaceMonitor

    public init(
        preferences: AppPreferencesStore = AppPreferencesStore(),
        loginService: any LoginItemServicing = RunnerSupervisorActor(),
        notificationClient: any AppNotificationClient = SystemNotificationClient()
    ) {
        self.preferences = preferences
        integration = AppIntegrationController(preferences: preferences, loginService: loginService)
        notifications = AppNotificationsController(preferences: preferences, client: notificationClient)
        healthMonitor = RunnerHealthMonitor(notifications: notifications, preferences: preferences)
        diskMonitor = DiskSpaceMonitor(preferences: preferences, notifications: notifications)
    }
}
