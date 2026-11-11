import AppShellFeature
import CoreModels
import Foundation
import Testing

@MainActor
struct AppNotificationTests {
    @Test("Background events never prompt for permission and respect the opt-in setting")
    func noAutomaticPrompt() async throws {
        let name = "octorunner-notifications-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let client = TestNotificationClient(state: .notDetermined)
        let controller = AppNotificationsController(preferences: preferences, client: client)
        let event = AppNotificationEvent(id: "runner-offline-1", kind: .runnerOffline, title: "Runner offline", message: "Test runner")
        #expect(await controller.publish(event) == false)
        preferences.notificationPolicy.enabled = true
        #expect(await controller.publish(event) == false)
        #expect(await client.requestCount == 0)
        #expect(await client.delivered.isEmpty)
    }

    @Test("Denied notification authorization cannot leave preferences enabled")
    func permissionDenied() async throws {
        let name = "octorunner-notifications-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let client = TestNotificationClient(state: .notDetermined)
        let controller = AppNotificationsController(preferences: preferences, client: client)
        await controller.setEnabled(true)
        #expect(controller.authorization == .denied)
        #expect(!preferences.notificationPolicy.enabled)
        #expect(await client.requestCount == 1)
    }

    @Test("Enabled event triggers are delivered once even during overlapping publication")
    func eventFilteringAndDeduplication() async throws {
        let name = "octorunner-notifications-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.notificationPolicy.enabled = true
        preferences.notificationPolicy.runnerOffline = false
        preferences.notificationPolicy.soundEnabled = false
        let client = TestNotificationClient(state: .allowed)
        let controller = AppNotificationsController(preferences: preferences, client: client)
        #expect(await controller.publish(AppNotificationEvent(id: "offline", kind: .runnerOffline, title: "Offline", message: "Runner")) == false)
        let event = AppNotificationEvent(id: "job-42-failed", kind: .jobFailure, title: "Job failed", message: "CI")
        async let first = controller.publish(event)
        async let second = controller.publish(event)
        let results = await [first, second]
        #expect(results.count(where: { $0 }) == 1)
        #expect(await client.delivered == [event])
        #expect(await client.lastSoundEnabled == false)
        #expect(await client.requestCount == 0)
    }
}

private actor TestNotificationClient: AppNotificationClient {
    private var state: NotificationAuthorizationState
    private(set) var requestCount = 0
    private(set) var delivered: [AppNotificationEvent] = []
    private(set) var lastSoundEnabled: Bool?

    init(state: NotificationAuthorizationState) { self.state = state }
    func authorizationStatus() -> NotificationAuthorizationState { state }
    func requestAuthorization() -> Bool {
        requestCount += 1
        state = .denied
        return false
    }
    func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) {
        delivered.append(event)
        lastSoundEnabled = soundEnabled
    }
}
