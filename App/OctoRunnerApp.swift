import AppKit
import AppShellFeature
import CoreModels
import SwiftData
import SwiftUI

public final class OctoRunnerAppDelegate: NSObject, NSApplicationDelegate {
    var integration: AppIntegrationController?

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        AppQuitConfirmation.shouldTerminate(after: AppQuitConfirmation.makeAlert().runModal())
            ? .terminateNow : .terminateCancel
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationDidUpdate(_ notification: Notification) {
        // Re-evaluate after AppKit processes window and preference changes, including
        // when the dashboard is closed. A visible Settings window also keeps its Dock icon.
        let hasVisibleWindow = NSApplication.shared.windows.contains { $0.canBecomeMain && $0.isVisible }
        integration?.applyDockVisibility(hasVisibleDashboard: hasVisibleWindow)
    }
}

@main
struct OctoRunnerApp: App {
    @NSApplicationDelegateAdaptor(OctoRunnerAppDelegate.self) private var appDelegate
    @State private var services = AppServices()
    private let modelContainer: ModelContainer = OctoRunnerPersistence.makeSharedContainer()

    var body: some Scene {
        @Bindable var preferences = services.preferences
        Window("OctoRunner", id: "main-dashboard") {
            MainShellView()
                .environment(services.preferences)
                .environment(services.integration)
                .environment(services.notifications)
                .environment(\.locale, preferences.language.locale)
                .frame(minWidth: 960, minHeight: 620)
                .task { appDelegate.integration = services.integration }
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.unified)

        Settings {
            SettingsWindowView()
                .environment(services.preferences)
                .environment(services.integration)
                .environment(services.notifications)
                .environment(\.locale, preferences.language.locale)
        }
        .modelContainer(modelContainer)

        MenuBarExtra("OctoRunner", systemImage: "infinity.circle.fill", isInserted: $preferences.showInMenuBar) {
            MenuBarStatusView()
                .environment(services.preferences)
                .environment(services.integration)
                .environment(services.notifications)
                .environment(\.locale, preferences.language.locale)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
