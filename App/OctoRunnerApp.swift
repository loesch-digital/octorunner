import AppKit
import AppShellFeature
import CoreModels
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
public final class OctoRunnerAppDelegate: NSObject, NSApplicationDelegate {
    let services = AppServices()
    let modelContainer = OctoRunnerPersistence.makeSharedContainer()
    private let notificationPresenter = NotificationPresentationDelegate()
    private var isQuitRequestPending = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        try? AppAuditEvent.started.record(in: modelContainer.mainContext)
        UNUserNotificationCenter.current().delegate = notificationPresenter
        services.healthMonitor.start(container: modelContainer)
        services.diskMonitor.start()
        services.storageMaintenance.start(container: modelContainer)
        services.jobFailureMonitor.start(container: modelContainer)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        services.healthMonitor.stop()
        services.diskMonitor.stop()
        services.storageMaintenance.stop()
        services.jobFailureMonitor.stop()
        try? AppAuditEvent.stopped.record(in: modelContainer.mainContext)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isQuitRequestPending else { return .terminateLater }
        let locale = services.preferences.language.locale
        let confirmation = AppQuitConfirmation.makeAlert(locale: locale)
        guard AppQuitConfirmation.shouldTerminate(after: confirmation.runModal()) else { return .terminateCancel }
        isQuitRequestPending = true
        Task {
            do {
                try await services.supervisor.shutdownForQuit()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                isQuitRequestPending = false
                sender.reply(toApplicationShouldTerminate: false)
                AppQuitConfirmation.makeBlockedAlert(error: error, locale: locale).runModal()
            }
        }
        return .terminateLater
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationDidUpdate(_ notification: Notification) {
        // Re-evaluate after AppKit processes window and preference changes, including
        // when the dashboard is closed. A visible Settings window also keeps its Dock icon.
        let hasVisibleWindow = NSApplication.shared.windows.contains { $0.canBecomeMain && $0.isVisible }
        services.integration.applyDockVisibility(hasVisibleDashboard: hasVisibleWindow)
    }
}

@main
struct OctoRunnerApp: App {
    @NSApplicationDelegateAdaptor(OctoRunnerAppDelegate.self) private var appDelegate

    var body: some Scene {
        let services = appDelegate.services
        let modelContainer = appDelegate.modelContainer
        @Bindable var preferences = services.preferences
        Window("OctoRunner", id: "main-dashboard") {
            LocalJobResultsSource { results in
                MainShellView(
                    historyRateBudget: services.historyRateBudget,
                    accountSession: services.accounts,
                    jobResults: results,
                    supervisor: services.supervisor
                )
            }
                .environment(services.preferences)
                .environment(services.integration)
                .environment(services.notifications)
                .environment(services.storageMaintenance)
                .environment(\.locale, preferences.language.locale)
                .frame(minWidth: 960, minHeight: 620)
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsWindowView(accountSession: services.accounts)
                .environment(services.preferences)
                .environment(services.integration)
                .environment(services.notifications)
                .environment(services.storageMaintenance)
                .environment(\.locale, preferences.language.locale)
        }
        .modelContainer(modelContainer)

        MenuBarExtra(isInserted: $preferences.showInMenuBar) {
            MenuBarStatusView(monitor: services.healthMonitor)
                .environment(services.preferences)
                .environment(services.integration)
                .environment(services.notifications)
                .environment(services.storageMaintenance)
                .environment(\.locale, preferences.language.locale)
                .modelContainer(modelContainer)
        } label: {
            RunnerMenuBarJobLabel(monitor: services.healthMonitor)
                .environment(services.preferences)
                .environment(\.locale, preferences.language.locale)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
