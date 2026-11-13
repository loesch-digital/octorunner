import CoreModels
import DesignSystem
import SwiftUI

public struct GeneralSettingsTab: View {
  @Environment(AppPreferencesStore.self) private var preferences

  public init() {}

  public var body: some View {
    @Bindable var preferences = preferences
    SettingsPage("General", subtitle: "Control app visibility and interface language.") {
      SettingsCard(
        "System integration", symbol: "macwindow",
        subtitle: "Choose where OctoRunner appears while it is running."
      ) {
        Toggle(isOn: $preferences.showInMenuBar) {
          Text("Show icon in menu bar", bundle: .module)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(Text("Show icon in menu bar", bundle: .module))
        .accessibilityHint(
          Text("Keeps the Dock icon available when the menu bar icon is hidden.", bundle: .module))
        Toggle(isOn: $preferences.hideDockIconWhenClosed) {
          Text("Hide Dock icon when windows are closed", bundle: .module)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityLabel(Text("Hide Dock icon when windows are closed", bundle: .module))
        .accessibilityHint(
          Text("Applies only while the menu bar icon is visible.", bundle: .module))
        Text(
          "Closing a window keeps OctoRunner running. Quitting removes its menu bar icon; installed runner LaunchAgents continue running.",
          bundle: .module)
        .font(.callout).foregroundStyle(OctoTheme.secondaryText)
      }
      SettingsCard(
        "Appearance and language", symbol: "globe",
        subtitle: "Choose the language used throughout OctoRunner."
      ) {
        Picker(selection: $preferences.language) {
          ForEach(AppLanguage.allCases) { language in
            Text(language.displayTitle).tag(language)
          }
        } label: {
          Text("Language", bundle: .module)
        }
        .accessibilityLabel(Text("Language", bundle: .module))
        .accessibilityHint(
          Text("Changes the interface language without restarting.", bundle: .module))
      }
    }
    .background(OctoTheme.surface)
  }
}
