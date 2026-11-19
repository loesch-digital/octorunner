import CoreModels
import DesignSystem
import SwiftData
import SwiftUI

struct SettingsUpdateCard: View {
    @Query private var runners: [RunnerEntity]
    @State private var controller: SettingsUpdateController
    @State private var checkRequested = false

    init(controller: SettingsUpdateController = SettingsUpdateController()) {
        _controller = State(initialValue: controller)
    }

    var body: some View {
        let summary = InstalledRunnerVersionSummary(runners.map(\.runnerVersion))
        SettingsCard("Versions and updates", symbol: "arrow.down.circle",
            subtitle: "Check stable OctoRunner releases and recorded runner versions.") {
            LabeledContent {
                Text(controller.currentVersion).textSelection(.enabled)
            } label: {
                Text("App version", bundle: .module)
            }
            LabeledContent {
                Text("Stable releases", bundle: .module)
            } label: {
                Text("Update channel", bundle: .module)
            }
            LabeledContent {
                if summary.versions.isEmpty {
                    Text("Not available", bundle: .module)
                } else {
                    Text(summary.versions.joined(separator: ", ")).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } label: {
                Text("Recorded runner engine versions", bundle: .module)
            }
            if summary.runnerCount == 0 {
                Text("No runners registered", bundle: .module)
                    .font(.callout).foregroundStyle(OctoTheme.secondaryText)
            } else if summary.hasUnknownVersion {
                Text("Some registered runner versions are unavailable.", bundle: .module)
                    .font(.callout).foregroundStyle(OctoTheme.secondaryText)
            }
            ViewThatFits(in: .horizontal) {
                HStack { checkButton; releasesLink }
                VStack(alignment: .leading) { checkButton; releasesLink }
            }
            if controller.isChecking {
                ProgressView { Text("Checking for updates…", bundle: .module) }
                    .controlSize(.small)
                    .accessibilityLabel(Text("Checking for updates…", bundle: .module))
            } else if controller.checkFailed {
                Text("Update check failed. Try again.", bundle: .module)
                    .foregroundStyle(OctoTheme.errorRed)
            } else if let info = controller.info {
                if info.isUpdateAvailable {
                    Text("A newer stable release is available: \(info.latestVersion)", bundle: .module)
                } else {
                    Text("No newer stable release is available.", bundle: .module)
                }
            }
        }
        .task(id: checkRequested) {
            guard checkRequested else { return }
            await controller.checkForUpdates()
            guard !Task.isCancelled else { return }
            checkRequested = false
        }
        .onDisappear { checkRequested = false }
    }

    private var checkButton: some View {
        Button { checkRequested = true } label: {
            Text("Check for updates", bundle: .module)
        }
        .disabled(checkRequested || controller.isChecking)
        .accessibilityLabel(Text("Check for updates", bundle: .module))
        .accessibilityHint(Text("Queries GitHub for the latest stable release. No update is installed automatically.", bundle: .module))
    }

    private var releasesLink: some View {
        Link(destination: URL(string: "https://github.com/loesch-digital/octorunner/releases")!) {
            Text("View releases on GitHub", bundle: .module)
        }
        .accessibilityLabel(Text("View releases on GitHub", bundle: .module))
        .accessibilityHint(Text("Opens release notes and app downloads in your browser.", bundle: .module))
    }
}
