import AppShellFeature
import CoreModels
import SwiftData
import SwiftUI

@main
struct OctoRunnerApp: App {
    @State private var preferences = AppPreferencesStore()

    private let modelContainer: ModelContainer = OctoRunnerPersistence.makeSharedContainer()

    var body: some Scene {
        WindowGroup("OctoRunner", id: "main-dashboard") {
            MainShellView()
                .environment(preferences)
                .frame(minWidth: 960, minHeight: 620)
                .preferredColorScheme(.dark)
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
