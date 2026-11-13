import Foundation

/// Notification metadata only. Never pass raw runner logs or credentials here.
public struct AppNotificationEvent: Sendable, Equatable {
    public let id: String
    public let kind: AppNotificationKind
    public let title: String
    public let message: String

    public init(id: String, kind: AppNotificationKind, title: String, message: String) {
        self.id = id
        self.kind = kind
        self.title = title
        self.message = message
    }
}
