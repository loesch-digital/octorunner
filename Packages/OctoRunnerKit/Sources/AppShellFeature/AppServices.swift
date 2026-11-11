import CoreModels
import RunnerEngine

/// Shared app lifetime services. Construction never requests system permissions.
@MainActor
public final class AppServices {
    public let preferences: AppPreferencesStore
    public let integration: AppIntegrationController
    public let notifications: AppNotificationsController

    public init(
        preferences: AppPreferencesStore = AppPreferencesStore(),
        loginService: any LoginItemServicing = RunnerSupervisorActor(),
        notificationClient: any AppNotificationClient = SystemNotificationClient()
    ) {
        self.preferences = preferences
        integration = AppIntegrationController(preferences: preferences, loginService: loginService)
        notifications = AppNotificationsController(preferences: preferences, client: notificationClient)
    }
}
