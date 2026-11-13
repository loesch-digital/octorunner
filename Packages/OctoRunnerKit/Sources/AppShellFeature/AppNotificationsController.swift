import CoreModels
import Foundation
import Observation

@Observable
@MainActor
public final class AppNotificationsController {
    public private(set) var authorization: NotificationAuthorizationState = .notDetermined
    public private(set) var isRequestingPermission = false
    public var errorMessage: String?

    @ObservationIgnored private let preferences: AppPreferencesStore
    @ObservationIgnored private let client: any AppNotificationClient
    @ObservationIgnored private var inFlight: Set<String> = []
    @ObservationIgnored private var deliveredIDs: Set<String> = []
    @ObservationIgnored private var deliveryOrder: [String] = []

    public init(preferences: AppPreferencesStore, client: any AppNotificationClient = SystemNotificationClient()) {
        self.preferences = preferences
        self.client = client
    }

    /// Call only in response to the user's notification setting change.
    public func setEnabled(_ enabled: Bool) async {
        guard !isRequestingPermission else { return }
        guard enabled else {
            preferences.notificationPolicy.enabled = false
            return
        }
        isRequestingPermission = true
        errorMessage = nil
        defer { isRequestingPermission = false }
        do {
            let actual = await client.authorizationStatus()
            try Task.checkCancellation()
            if actual == .notDetermined { _ = try await client.requestAuthorization() }
            authorization = await client.authorizationStatus()
            preferences.notificationPolicy.enabled = authorization == .allowed
        } catch is CancellationError {
            preferences.notificationPolicy.enabled = false
        } catch {
            preferences.notificationPolicy.enabled = false
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    public func publish(_ event: AppNotificationEvent) async -> Bool {
        guard !event.id.isEmpty, isEnabled(event.kind),
              !inFlight.contains(event.id), !deliveredIDs.contains(event.id) else { return false }
        inFlight.insert(event.id)
        defer { inFlight.remove(event.id) }
        let actual = await client.authorizationStatus()
        guard !Task.isCancelled, actual == .allowed, isEnabled(event.kind) else { return false }
        do {
            try await client.deliver(event, soundEnabled: preferences.notificationPolicy.soundEnabled)
            deliveredIDs.insert(event.id)
            deliveryOrder.append(event.id)
            if deliveryOrder.count > 512 { deliveredIDs.remove(deliveryOrder.removeFirst()) }
            return true
        } catch is CancellationError {
            return false
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func isEnabled(_ kind: AppNotificationKind) -> Bool {
        let policy = preferences.notificationPolicy
        guard policy.enabled else { return false }
        switch kind {
        case .runnerOffline: return policy.runnerOffline
        case .runnerOnline: return policy.runnerOnline
        case .runnerError: return policy.runnerError
        case .jobFailure: return policy.jobFailure
        case .lowDiskSpace: return policy.lowDiskSpace
        }
    }
}
