import DesignSystem
import SwiftUI

struct RunnerMigrationConfirmation: View {
    let runnerName: String
    let account: String
    let source: URL
    let destination: URL
    let scope: URL
    let group: String?
    let labels: [String]
    let launchAgent: Bool
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Confirm Runner Migration", bundle: .module)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text(runnerName).font(.headline)
                    Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                        row("GitHub account", "@\(account)")
                        row("GitHub Scope", scope.absoluteString)
                        if let group { row("Runner Group", group) }
                        row("Labels", labels.joined(separator: ", "))
                        row("Current Folder", source.path)
                        row("Managed Folder", destination.path)
                    }
                    if launchAgent {
                        Text("OctoRunner will start the new runner as a macOS background service.", bundle: .module)
                    } else {
                        Text("OctoRunner will run the new runner while the app is open.", bundle: .module)
                    }
                    Text("The previous runner must stay offline. OctoRunner will replace its GitHub registration and create a fresh working directory. The original folder and job files stay in place.", bundle: .module)
                    Text("If registration is interrupted, use the recovery information in Runner Settings before restarting either installation.", bundle: .module)
                        .foregroundStyle(OctoTheme.secondaryText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button(role: .cancel, action: onCancel) { Text("Cancel", bundle: .module) }
                    .accessibilityHint(Text("Closes the review without changing the runner.", bundle: .module))
                Button(action: onConfirm) { Text("Replace GitHub Registration", bundle: .module) }
                    .buttonStyle(.borderedProminent)
                    .tint(OctoTheme.accentBlue)
                    .accessibilityHint(Text("Registers the prepared installation with GitHub.", bundle: .module))
            }
        }
        .padding(20)
        .frame(minWidth: 400, idealWidth: 460, maxWidth: 600, minHeight: 400, idealHeight: 510)
        .background(OctoTheme.surfaceLowest)
    }

    private func row(_ label: LocalizedStringKey, _ value: String) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label, bundle: .module).foregroundStyle(OctoTheme.secondaryText)
            Text(value).textSelection(.enabled)
        }
    }
}

#Preview("Migration · Deutsch") {
    RunnerMigrationConfirmation(
        runnerName: "Mac mini Build Runner", account: "example",
        source: URL(filePath: "/Users/example/Build/actions-runner"),
        destination: URL(filePath: "/Users/example/Library/Application Support/io.octorunner.macos/runners/Mac mini Build Runner"),
        scope: URL(string: "https://github.com/example")!, group: "Build",
        labels: ["self-hosted", "macOS", "ARM64", "xcode"],
        launchAgent: true, onCancel: {}, onConfirm: {}
    )
    .environment(\.locale, Locale(identifier: "de"))
    .preferredColorScheme(.dark)
}
