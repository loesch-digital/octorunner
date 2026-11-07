import AppKit
import AppShellFeature
import CoreModels
import SwiftData
import SwiftUI

public final class OctoRunnerAppDelegate: NSObject, NSApplicationDelegate {
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Keep OctoRunner MenuBar Extra and background supervision alive when the Dashboard window is closed
        false
    }
}

@main
struct OctoRunnerApp: App {
    @NSApplicationDelegateAdaptor(OctoRunnerAppDelegate.self) private var appDelegate
    @State private var preferences = AppPreferencesStore()

    private let modelContainer: ModelContainer = OctoRunnerPersistence.makeSharedContainer()

    var body: some Scene {
        Window("OctoRunner", id: "main-dashboard") {
            MainShellView()
                .environment(preferences)
                .frame(minWidth: 960, minHeight: 620)
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.unified)

        MenuBarExtra("OctoRunner", systemImage: "infinity.circle.fill") {
            MenuBarStatusView()
                .environment(preferences)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
