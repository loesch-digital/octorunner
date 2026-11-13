import DesignSystem
import SwiftUI

public struct SettingsWindowView: View {
  @State private var selectedTab: SettingsTab = .general
  @State private var searchText = ""
  @State private var accountSession: AccountSessionController

  public init(accountSession: AccountSessionController = AccountSessionController()) {
    _accountSession = State(initialValue: accountSession)
  }

  public var body: some View {
    VStack(spacing: 0) {
      // Keep categories in the content hierarchy: automatic macOS TabView
      // navigation can migrate into the window toolbar and disappear when
      // these settings are embedded in the main dashboard.
      LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], spacing: 8) {
        ForEach(SettingsTab.allCases, id: \.self) { tab in
          Button {
            select(tab)
          } label: {
            VStack(spacing: 6) {
              Image(systemName: tab.systemImage)
                .font(.title3)
              Text(tab.title, bundle: .module)
                .font(.callout)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 64)
            .padding(.horizontal, 8)
            .foregroundStyle(selectedTab == tab ? OctoTheme.accentBlue : .primary)
            .background(
              selectedTab == tab ? OctoTheme.surfaceHigh : OctoTheme.surfaceLow,
              in: .rect(cornerRadius: 8)
            )
            .overlay {
              if selectedTab == tab {
                RoundedRectangle(cornerRadius: 8)
                  .strokeBorder(OctoTheme.accentBlue, lineWidth: 2)
              }
            }
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel(Text(tab.title, bundle: .module))
          .accessibilityHint(Text("Open this settings category", bundle: .module))
          .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        }
      }
      .padding()
      .background(OctoTheme.surfaceLow)
      Divider()
      Group {
        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          selectedContent
        } else {
          SettingsSearchResults(query: searchText, select: select)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(minWidth: 620, idealWidth: 680, minHeight: 480, idealHeight: 520)
    .searchable(text: $searchText, prompt: Text("Search settings…", bundle: .module))
  }

  private func select(_ tab: SettingsTab) {
    selectedTab = tab
    searchText = ""
  }

  @ViewBuilder private var selectedContent: some View {
    switch selectedTab {
    case .general: GeneralSettingsTab()
    case .background: BackgroundSettingsTab()
    case .failover: FailoverSettingsTab()
    case .auth: SecurityTokenSettingsTab(accountSession: accountSession)
    case .notifications: AlertsSettingsTab()
    }
  }
}
