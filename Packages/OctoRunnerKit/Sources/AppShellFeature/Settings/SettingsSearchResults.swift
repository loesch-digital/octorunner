import DesignSystem
import SwiftUI

struct SettingsSearchResults: View {
  @Environment(\.locale) private var locale
  let query: String
  let select: (SettingsTab) -> Void

  var body: some View {
    let matches = SettingsTab.matching(query, locale: locale)
    if matches.isEmpty {
      ContentUnavailableView.search
    } else {
      SettingsPage("Matching settings", subtitle: "Choose a category to open its matching options.")
      {
        ForEach(matches, id: \.self) { tab in
          Button {
            select(tab)
          } label: {
            HStack(spacing: 12) {
              Label {
                Text(tab.title, bundle: .module)
              } icon: {
                Image(systemName: tab.systemImage)
              }
              Spacer()
              Image(systemName: "chevron.right").accessibilityHidden(true)
            }
            .padding()
            .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(tab.title, bundle: .module))
          .accessibilityHint(Text("Open this settings category", bundle: .module))
          .accessibilityIdentifier("settings.search.\(tab.rawValue)")
        }
      }
    }
  }
}
