import CoreModels
import DesignSystem
import RunnerEngine
import SwiftUI

struct RunnerMigrationControls: View {
    @Environment(\.locale) private var locale

    let runner: RunnerEntity
    let launchAgents: RunnerLaunchAgentInspector?
    let needsRecovery: Bool
    let isSaving: Bool
    let isMigrating: Bool
    @Binding var registerBackgroundService: Bool
    let showRecovery: () -> Void
    let reviewMigration: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if needsRecovery {
                Button(action: showRecovery) {
                    Label { Text("Review Migration Recovery", bundle: .module) } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
                .accessibilityHint(Text("Opens the last recorded migration stage and recovery instructions.", bundle: .module))
                .disabled(isSaving)
            }
            if runner.isImportedLocal {
                importedRunnerCard
            } else if let launchAgents, let target = runner.launchAgentTarget {
                RunnerLaunchAgentPanel(runnerID: runner.id, target: target, inspector: launchAgents)
                    .padding(14)
                    .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
            } else if runner.executionMode == .direct {
                Text("This runner is managed by OctoRunner while the app is open.", bundle: .module)
                    .foregroundStyle(OctoTheme.secondaryText)
            } else {
                Text("No managed LaunchAgent is assigned to this runner.", bundle: .module)
                    .foregroundStyle(OctoTheme.secondaryText)
            }
        }
    }

    private var importedRunnerCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.right.doc.on.clipboard")
                    .foregroundStyle(OctoTheme.accentBlue)
                Text(AppLocalization.string("Migrate Imported Runner into OctoRunner Managed Pool", locale: locale))
                    .font(.system(size: 13, weight: .bold))
            }

            Text("Stop the existing runner and disable its previous automatic startup before reviewing the migration.", bundle: .module)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Toggle(isOn: $registerBackgroundService) {
                Text("Automatic Background Start on macOS Login", bundle: .module)
            }
            .accessibilityHint(Text("Installs a LaunchAgent when the runner is migrated.", bundle: .module))
            .disabled(isMigrating)

            Button(action: reviewMigration) {
                HStack(spacing: 6) {
                    if isMigrating {
                        ProgressView().controlSize(.small)
                        Text(AppLocalization.string("Migrating Runner…", locale: locale))
                    } else {
                        Image(systemName: "bolt.horizontal.circle.fill")
                        Text("Review Runner Migration", bundle: .module)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .accessibilityHint(Text("Checks the selected runner folder and its GitHub registration.", bundle: .module))
            .disabled(isMigrating || isSaving || needsRecovery)
        }
        .padding(14)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.accentBlue.opacity(0.5), lineWidth: 1)
        }
    }
}
