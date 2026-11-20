import DesignSystem
import RunnerEngine
import SwiftUI

struct RunnerMigrationRecoveryView: View {
    @Environment(\.dismiss) private var dismiss
    let recovery: RunnerMigrationRecovery?
    let error: String?
    let isWorking: Bool
    let discard: (() -> Void)?
    let retry: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Runner Migration Recovery", bundle: .module)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let recovery {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(stageMessage(recovery.stage), bundle: .module)
                        LabeledContent {
                            Text(recovery.source.path).textSelection(.enabled)
                        } label: {
                            Text("Current Folder", bundle: .module)
                        }
                        LabeledContent {
                            Text(recovery.destination.path).textSelection(.enabled)
                        } label: {
                            Text("Managed Folder", bundle: .module)
                        }
                        LabeledContent {
                            Text(String(recovery.oldRemoteID)).textSelection(.enabled)
                        } label: {
                            Text("Previous GitHub Runner ID", bundle: .module)
                        }
                        if let remoteID = recovery.newRemoteID {
                            LabeledContent {
                                Text(String(remoteID)).textSelection(.enabled)
                            } label: {
                                Text("New GitHub Runner ID", bundle: .module)
                            }
                        }
                        Text("Check the runner entry on GitHub and keep the original service stopped until you know which installation is registered.", bundle: .module)
                            .foregroundStyle(OctoTheme.secondaryText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("OctoRunner could not read the migration journal. Review the original folder and the GitHub runner entry before starting a runner.", bundle: .module)
            }

            HStack {
                if isWorking { ProgressView().controlSize(.small) }
                Spacer()
                Button { dismiss() } label: { Text("Close", bundle: .module) }
                    .accessibilityHint(Text("Closes the recovery instructions.", bundle: .module))
                if let discard {
                    Button(action: discard) { Text("Discard Preparation", bundle: .module) }
                        .accessibilityHint(Text("Removes only the verified temporary installation.", bundle: .module))
                }
                if let retry {
                    Button(action: retry) { Text("Resume Verified Migration", bundle: .module) }
                        .accessibilityHint(Text("Verifies the existing registration, saves any pending changes and starts the managed runner.", bundle: .module))
                }
            }
            .disabled(isWorking)
            if let error {
                Text(error).foregroundStyle(OctoTheme.errorRed).textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 420, idealWidth: 480, maxWidth: 600, minHeight: 280, idealHeight: 360)
        .background(OctoTheme.surfaceLowest)
        .interactiveDismissDisabled(isWorking)
    }

    private func stageMessage(_ stage: RunnerMigrationRecovery.Stage) -> LocalizedStringKey {
        switch stage {
        case .preparing:
            "Preparation was interrupted before attempting to replace the GitHub registration."
        case .registering:
            "GitHub may already have replaced the registration. Use GitHub’s runner settings to determine which installation can be recovered."
        case .registered, .committing:
            "OctoRunner verified the new registration and can resume from the last saved step."
        case .starting:
            "OctoRunner saved the updated runner. You can retry the managed startup here."
        }
    }
}
