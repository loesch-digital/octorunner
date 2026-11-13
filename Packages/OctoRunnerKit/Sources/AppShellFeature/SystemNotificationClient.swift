import Foundation
import UserNotifications

public actor SystemNotificationClient: AppNotificationClient {
    public init() {}

    // The macOS 15 SDK does not declare UNNotificationSettings Sendable.
    // Read and reduce it on the nonisolated executor; only our value enum crosses back.
    public nonisolated func authorizationStatus() async -> NotificationAuthorizationState {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.authorizationState(for: settings.authorizationStatus)
    }

    nonisolated static func authorizationState(for status: UNAuthorizationStatus) -> NotificationAuthorizationState {
        switch status {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }

    public func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    public func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) async throws {
        try Task.checkCancellation()
        let content = UNMutableNotificationContent()
        content.title = event.title
        content.body = event.message
        if soundEnabled { content.sound = .default }
        let request = UNNotificationRequest(identifier: event.id, content: content, trigger: nil)
        try await UNUserNotificationCenter.current().add(request)
    }
}
