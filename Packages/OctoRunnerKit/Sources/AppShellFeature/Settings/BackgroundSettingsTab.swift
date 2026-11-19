import CoreModels
import DesignSystem
import RunnerEngine
import SwiftData
import SwiftUI

public struct BackgroundSettingsTab: View {
  @Environment(AppPreferencesStore.self) private var preferences

  private let launchAgents: RunnerLaunchAgentInspector?

  public init(launchAgents: RunnerLaunchAgentInspector? = nil) {
    self.launchAgents = launchAgents
  }

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
      if let launchAgents {
        RunnerLaunchAgentsCard(inspector: launchAgents)
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

private struct RunnerLaunchAgentsCard: View {
  @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
  let inspector: RunnerLaunchAgentInspector

  var body: some View {
    let candidates = runners.compactMap { runner in
      runner.launchAgentTarget.map { (id: runner.id, target: $0) }
    }
    SettingsCard(
      "Runner LaunchAgents", symbol: "gearshape.2",
      subtitle: "Inspect the installed configuration and current status of each runner service."
    ) {
      if candidates.isEmpty {
        Text("No runner LaunchAgents are configured.", bundle: .module)
          .foregroundStyle(OctoTheme.secondaryText)
      } else {
        ForEach(candidates, id: \.id) { candidate in
          RunnerLaunchAgentRow(runnerID: candidate.id, target: candidate.target, inspector: inspector)
        }
      }
    }
  }
}

private struct RunnerLaunchAgentRow: View {
  @State private var expanded = false
  let runnerID: UUID
  let target: RunnerLaunchAgentTarget
  let inspector: RunnerLaunchAgentInspector

  var body: some View {
    DisclosureGroup(isExpanded: $expanded) {
      if expanded {
        RunnerLaunchAgentPanel(runnerID: runnerID, target: target, inspector: inspector)
          .padding(.top, 8)
      }
    } label: {
      Text(verbatim: target.name)
    }
    .accessibilityHint(Text("Shows the configuration and status of this service.", bundle: .module))
  }
}
