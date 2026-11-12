import CoreModels
import DesignSystem
import SwiftUI

public struct AlertsSettingsTab: View {
    @Environment(AppPreferencesStore.self) private var preferences
    @Environment(AppNotificationsController.self) private var notifications
    @State private var permissionTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                Toggle(isOn: notificationBinding) {
                    Text("Enable macOS notifications", bundle: .module)
                }
                .disabled(notifications.isRequestingPermission)
                .accessibilityLabel(Text("Enable macOS notifications", bundle: .module))
                .accessibilityHint(Text("Requests permission only when you enable this setting.", bundle: .module))
                if notifications.authorization == .denied {
                    Text("Notifications are blocked. Allow them for OctoRunner in System Settings → Notifications, then enable this setting again.", bundle: .module)
                        .fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(OctoTheme.warningOrange)
                }
                if let message = notifications.errorMessage {
                    Text(message).foregroundStyle(OctoTheme.errorRed).textSelection(.enabled)
                }
                Toggle(isOn: $preferences.notificationPolicy.soundEnabled) {
                    Text("Play notification sounds", bundle: .module)
                }
                .disabled(!preferences.notificationPolicy.enabled)
                .accessibilityLabel(Text("Play notification sounds", bundle: .module))
                .accessibilityHint(Text("Uses the macOS default notification sound.", bundle: .module))
            } header: {
                Text("Notification Center", bundle: .module)
            } footer: {
                Text("Choose banners or alerts in macOS System Settings. OctoRunner cannot override your system presentation settings.", bundle: .module)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section {
                Toggle(isOn: $preferences.notificationPolicy.runnerOnline) {
                    Text("Runner comes online", bundle: .module)
                }
                .accessibilityLabel(Text("Runner comes online", bundle: .module))
                .accessibilityHint(Text("Reports a detected transition to online, excluding initial app startup.", bundle: .module))
                Toggle(isOn: $preferences.notificationPolicy.runnerOffline) {
                    Text("Runner goes offline", bundle: .module)
                }
                .accessibilityLabel(Text("Runner goes offline", bundle: .module))
                .accessibilityHint(Text("Reports a detected transition from online to offline.", bundle: .module))
                Toggle(isOn: $preferences.notificationPolicy.runnerError) {
                    Text("Runner enters an error state", bundle: .module)
                }
                .accessibilityLabel(Text("Runner enters an error state", bundle: .module))
                .accessibilityHint(Text("Reports a detected transition to a runner error state.", bundle: .module))
                .disabled(true)
                Text("Runner error alerts require crash supervision in v0.6.0 and are not active yet.", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle(isOn: $preferences.notificationPolicy.jobFailure) {
                    Text("Local workflow job fails", bundle: .module)
                }
                .accessibilityLabel(Text("Local workflow job fails", bundle: .module))
                .accessibilityHint(Text("Reports failures assigned to a local runner.", bundle: .module))
                Toggle(isOn: $preferences.notificationPolicy.lowDiskSpace) {
                    Text("Low disk space", bundle: .module)
                }
                .accessibilityLabel(Text("Low disk space", bundle: .module))
                .accessibilityHint(Text("Warns when available space crosses the configured storage threshold.", bundle: .module))
            } header: {
                Text("Events", bundle: .module)
            } footer: {
                Text("Runner events track local process availability. Monitoring continues with windows closed. Quitting OctoRunner stops monitoring and new status notifications.", bundle: .module)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .disabled(!preferences.notificationPolicy.enabled)
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .background(OctoTheme.surface)
        .onDisappear { permissionTask?.cancel() }
    }

    private var notificationBinding: Binding<Bool> {
        Binding(get: { preferences.notificationPolicy.enabled }, set: changePermission)
    }

    private func changePermission(_ enabled: Bool) {
        permissionTask?.cancel()
        permissionTask = Task { await notifications.setEnabled(enabled) }
    }
}
