import DesignSystem
import SwiftUI

struct SettingsCard<Content: View>: View {
  let title: LocalizedStringKey
  let symbol: String
  let subtitle: LocalizedStringKey
  private let content: Content

  init(
    _ title: LocalizedStringKey, symbol: String, subtitle: LocalizedStringKey,
    @ViewBuilder content: () -> Content
  ) {
    self.title = title
    self.symbol = symbol
    self.subtitle = subtitle
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: symbol).font(.title2).foregroundStyle(OctoTheme.accentBlue)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 4) {
          Text(title, bundle: .module).font(.headline).accessibilityAddTraits(.isHeader)
          Text(subtitle, bundle: .module).font(.callout).foregroundStyle(OctoTheme.secondaryText)
        }
        .fixedSize(horizontal: false, vertical: true)
        Spacer(minLength: 0)
      }
      Divider()
      content
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(OctoTheme.surface, in: .rect(cornerRadius: 12))
  }
}
