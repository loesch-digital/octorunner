import AppKit
import DesignSystem
import SwiftUI

struct BackgroundMonitoringSettingsCard: View {
    @Environment(BackgroundMonitoringController.self) private var monitoring: BackgroundMonitoringController?
    @Environment(\.controlActiveState) private var controlActiveState

    var body: some View {
        if let monitoring {
            SettingsCard(
                "Local background monitoring", symbol: "waveform.path",
                subtitle: "Keep checking local runner processes after you quit OctoRunner."
            ) {
                Toggle(isOn: registration(for: monitoring)) {
                    Text("Monitor local runners after quitting", bundle: .module)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityLabel(Text("Monitor local runners after quitting", bundle: .module))
                .accessibilityHint(Text("Registers a macOS background item for your account.", bundle: .module))
                .accessibilityIdentifier("local-background-monitoring")
                .disabled(monitoring.isApplying)
                status(for: monitoring)
                if monitoring.hasError {
                    Text("The background service could not be configured.", bundle: .module)
                        .foregroundStyle(OctoTheme.errorRed)
                        .textSelection(.enabled)
                }
            }
            .task(id: controlActiveState) { await monitoring.refresh() }
        }
    }

    private func registration(for monitoring: BackgroundMonitoringController) -> Binding<Bool> {
        Binding(
            get: { monitoring.state == .enabled || monitoring.state == .requiresApproval },
            set: { isEnabled in Task { await monitoring.setEnabled(isEnabled) } }
        )
    }

    @ViewBuilder private func status(for monitoring: BackgroundMonitoringController) -> some View {
        switch monitoring.state {
        case .disabled:
            Text("Background monitoring is off.", bundle: .module)
                .foregroundStyle(OctoTheme.secondaryText)
        case .enabled:
            Text("Ready to monitor locally after quitting. GitHub updates resume when you reopen OctoRunner.", bundle: .module)
                .foregroundStyle(OctoTheme.secondaryText)
        case .requiresApproval:
            Text("Approve OctoRunner in System Settings → General → Login Items.", bundle: .module)
                .foregroundStyle(OctoTheme.warningOrange)
        case .unavailable:
            Text("Background monitoring is unavailable for this app installation.", bundle: .module)
                .foregroundStyle(OctoTheme.secondaryText)
        }
    }
}
