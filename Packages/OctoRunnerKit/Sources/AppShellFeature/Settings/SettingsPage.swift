import DesignSystem
import SwiftUI

struct SettingsPage<Content: View>: View {
  let title: LocalizedStringKey
  let subtitle: LocalizedStringKey
  private let content: Content

  init(
    _ title: LocalizedStringKey, subtitle: LocalizedStringKey, @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        VStack(alignment: .leading, spacing: 6) {
          Text(title, bundle: .module).font(.title2.bold()).accessibilityAddTraits(.isHeader)
          Text(subtitle, bundle: .module).foregroundStyle(OctoTheme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        content
        Label {
          Text("Changes are saved automatically", bundle: .module)
        } icon: {
          Image(systemName: "checkmark.circle").accessibilityHidden(true)
        }
        .font(.callout).foregroundStyle(OctoTheme.secondaryText)
      }
      .frame(maxWidth: 960, alignment: .leading)
      .padding(20)
      .frame(maxWidth: .infinity)
    }
    .toggleStyle(.switch)
    .scrollBounceBehavior(.basedOnSize)
    .background(OctoTheme.surfaceLowest)
  }
}
