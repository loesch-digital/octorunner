import CoreModels
import DesignSystem
import SwiftUI

public struct BackgroundSettingsTab: View {
  @Environment(AppPreferencesStore.self) private var preferences

  public init() {}

  public var body: some View {
    @Bindable var preferences = preferences
    SettingsPage(
      "Autostart & Background",
      subtitle: "Keep app startup separate from your independent runner services."
    ) {
      SettingsCard(
        "System startup & login persistence", symbol: "power",
        subtitle: "Choose whether the OctoRunner app opens when you sign in."
      ) {
        LoginItemSettingsControl()
        Text(
          "The app login item is independent of installed runner LaunchAgents.", bundle: .module)
        .font(.callout).foregroundStyle(OctoTheme.secondaryText)
      }
      SettingsCard(
        "New runner environment", symbol: "terminal",
        subtitle: "Set the shell environment and tool paths for newly created runners."
      ) {
        Picker(selection: $preferences.runtimePolicy.shell) {
          ForEach(RunnerShell.allCases) { shell in
            Text(shell.rawValue).tag(shell)
          }
        } label: {
          Text("Runner SHELL environment", bundle: .module)
        }
        .accessibilityLabel(Text("Runner SHELL environment", bundle: .module))
        .accessibilityHint(
          Text("Sets the shell environment for newly created runners.", bundle: .module))

        Toggle(isOn: $preferences.inheritHostPath) {
          Text("Inherit OctoRunner's PATH", bundle: .module)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(Text("Inherit OctoRunner's PATH", bundle: .module))
        .accessibilityHint(
          Text(
            "Uses absolute PATH entries and adds Homebrew tools. When disabled, only system directories are used.",
            bundle: .module))
        Text(
          "Applies when creating runners. GitHub's startup scripts still use Bash; each workflow defines the shell for its own steps.",
          bundle: .module
        )
        .fixedSize(horizontal: false, vertical: true)
        .font(.callout).foregroundStyle(OctoTheme.secondaryText)
      }
    }
    .background(OctoTheme.surface)
  }
}
