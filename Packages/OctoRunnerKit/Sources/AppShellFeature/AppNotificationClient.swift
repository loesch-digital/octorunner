import Foundation

public protocol AppNotificationClient: Sendable {
    func authorizationStatus() async -> NotificationAuthorizationState
    func requestAuthorization() async throws -> Bool
    func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) async throws
}
