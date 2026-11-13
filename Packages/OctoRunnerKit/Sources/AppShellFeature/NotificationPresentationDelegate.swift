import Foundation
import UserNotifications

/// Foreground presentation still respects macOS settings and each event's sound.
public final class NotificationPresentationDelegate: NSObject, UNUserNotificationCenterDelegate {
    public static var foregroundOptions: UNNotificationPresentationOptions { [.banner, .list, .sound] }

    public nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(Self.foregroundOptions)
    }
}
