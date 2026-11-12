import CoreModels
import DesignSystem
import SwiftUI

public struct FailoverSettingsTab: View {
  @Environment(AppPreferencesStore.self) private var preferences

  public init() {}

  public var body: some View {
    @Bindable var preferences = preferences
    SettingsPage("Failover", subtitle: "Configure recovery for newly installed runner services.") {
      SettingsCard(
        "New runner LaunchAgents", symbol: "arrow.clockwise",
        subtitle: "Choose how launchd restarts a runner after its process exits."
      ) {
        Picker(selection: $preferences.runtimePolicy.restartPolicy) {
          Text("Always restart", bundle: .module).tag(RunnerRestartPolicy.always)
          Text("Restart after an error", bundle: .module).tag(RunnerRestartPolicy.onNonZeroExit)
          Text("No automatic restart", bundle: .module).tag(RunnerRestartPolicy.manual)
        } label: {
          Text("Restart policy", bundle: .module)
        }
        .accessibilityLabel(Text("Restart policy", bundle: .module))
        .accessibilityHint(
          Text(
            "Controls how launchd restarts newly created runner services after they exit.",
            bundle: .module))
        Stepper(value: $preferences.runtimePolicy.restartDelaySeconds, in: 1...300) {
          LabeledContent {
            Text(preferences.runtimePolicy.restartDelaySeconds, format: .number)
          } label: {
            Text("Restart delay (seconds)", bundle: .module)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .accessibilityLabel(Text("Restart delay (seconds)", bundle: .module))
        .accessibilityHint(
          Text("Limits how frequently launchd attempts to restart a runner.", bundle: .module))
        Text(
          "Applies to newly created LaunchAgents. Existing runners keep their installed configuration. A service without automatic restart still starts once at login.",
          bundle: .module
        )
        .fixedSize(horizontal: false, vertical: true)
        .font(.callout).foregroundStyle(OctoTheme.secondaryText)
      }
    }
    .background(OctoTheme.surface)
  }
}
