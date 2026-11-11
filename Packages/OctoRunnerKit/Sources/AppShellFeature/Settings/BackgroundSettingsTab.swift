import CoreModels
import DesignSystem
import SwiftUI

public struct BackgroundSettingsTab: View {
    @Environment(AppPreferencesStore.self) private var preferences

    public init() {}

    public var body: some View {
        @Bindable var preferences = preferences
        Form {
            Section {
                LoginItemSettingsControl()
            } header: {
                Text("OctoRunner app", bundle: .module)
            } footer: {
                Text("The app login item is independent of installed runner LaunchAgents.", bundle: .module)
            }
            Section {
                Picker(selection: $preferences.runtimePolicy.shell) {
                    ForEach(RunnerShell.allCases) { shell in
                        Text(shell.rawValue).tag(shell)
                    }
                } label: {
                    Text("Runner SHELL environment", bundle: .module)
                }
                .accessibilityLabel(Text("Runner SHELL environment", bundle: .module))
                .accessibilityHint(Text("Sets the shell environment for newly created runners.", bundle: .module))

                Toggle(isOn: $preferences.inheritHostPath) {
                    Text("Inherit OctoRunner's PATH", bundle: .module)
                }
                .accessibilityLabel(Text("Inherit OctoRunner's PATH", bundle: .module))
                .accessibilityHint(Text("Uses absolute PATH entries and adds Homebrew tools. When disabled, only system directories are used.", bundle: .module))
            } header: {
                Text("New runner environment", bundle: .module)
            } footer: {
                Text("Applies when creating runners. GitHub's startup scripts still use Bash; each workflow defines the shell for its own steps.", bundle: .module)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .background(OctoTheme.surface)
    }
}
