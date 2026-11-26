#if DEBUG
@_spi(Testing) import AppShellFeature
import CoreModels
import SwiftData
import SwiftUI

struct OctoRunnerWorkflowUITestApp: App {
    private let fixture: WorkflowUITestFixture
    private let container: ModelContainer
    private let preferences: AppPreferencesStore

    init() {
        guard let path = ProcessInfo.processInfo.environment[WorkflowUITestFixture.directoryKey],
              let defaults = UserDefaults(suiteName: "OctoRunner.WorkflowUITest.\(UUID())") else {
            preconditionFailure("Missing workflow UI test configuration")
        }
        preferences = AppPreferencesStore(defaults: defaults)
        preferences.language = ProcessInfo.processInfo.environment["OCTORUNNER_WORKFLOW_UI_TEST_LANGUAGE"] == "de" ? .german : .english
        fixture = WorkflowUITestFixture(directory: URL(filePath: path))
        do { container = try fixture.container() }
        catch { preconditionFailure("Failed to create workflow UI fixture: \(error)") }
    }

    var body: some Scene {
        Window("OctoRunner Workflow Tests", id: "main-dashboard") {
            fixture.dashboard(preferences: preferences)
        }
        .modelContainer(container)
    }
}
#endif
