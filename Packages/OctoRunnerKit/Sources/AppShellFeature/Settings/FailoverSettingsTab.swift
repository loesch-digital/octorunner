import CoreModels
import DesignSystem
import SwiftUI

public struct FailoverSettingsTab: View {
  @Environment(AppPreferencesStore.self) private var preferences

  public init() {}

  public var body: some View {
    @Bindable var preferences = preferences
    SettingsPage("Failover", subtitle: "Control how OctoRunner restarts its directly managed runners.") {
      SettingsCard(
        "Process recovery", symbol: "arrow.clockwise",
        subtitle: "These settings apply while OctoRunner is running."
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
            "Controls when a directly managed runner restarts after a process exit.",
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
          Text("Sets the wait before each automatic restart.", bundle: .module))
        Stepper(value: $preferences.runtimePolicy.quarantineThreshold, in: 1...100) {
          LabeledContent {
            Text(preferences.runtimePolicy.quarantineThreshold, format: .number)
          } label: {
            Text("Failures before quarantine", bundle: .module)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .accessibilityLabel(Text("Failures before quarantine", bundle: .module))
        .accessibilityHint(Text("Stops automatic recovery after this many consecutive failures.", bundle: .module))
        Text(
          "New LaunchAgents use the selected restart rule and delay. Existing LaunchAgents keep their installed configuration.",
          bundle: .module
        )
        .fixedSize(horizontal: false, vertical: true)
        .font(.callout).foregroundStyle(OctoTheme.secondaryText)
      }
      SettingsCard(
        "Low Power Mode", symbol: "battery.25percent",
        subtitle: "Defer new starts while macOS is saving energy."
      ) {
        Toggle(isOn: $preferences.runtimePolicy.batterySaverEnabled) {
          Text("Defer runner starts in Low Power Mode", bundle: .module)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(Text("Defer runner starts in Low Power Mode", bundle: .module))
        .accessibilityHint(Text("Running jobs continue. Pending starts resume when macOS leaves Low Power Mode.", bundle: .module))
      }
    }
    .background(OctoTheme.surface)
  }
}
