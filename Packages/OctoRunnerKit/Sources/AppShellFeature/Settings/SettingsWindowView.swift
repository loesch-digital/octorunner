import DesignSystem
import CoreModels
import RunnerEngine
import SwiftData
import SwiftUI

public struct SettingsWindowView: View {
  @State private var selectedTab: SettingsTab = .general
  @State private var searchText = ""
  @State private var accountSession: AccountSessionController
  private let launchAgents: RunnerLaunchAgentInspector?

  public init(accountSession: AccountSessionController = AccountSessionController(), launchAgents: RunnerLaunchAgentInspector? = nil) {
    _accountSession = State(initialValue: accountSession)
    self.launchAgents = launchAgents
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
    case .background: BackgroundSettingsTab(launchAgents: launchAgents)
    case .failover: FailoverSettingsTab()
    case .storage: StorageSettingsTab()
    case .auth: SecurityTokenSettingsTab(accountSession: accountSession)
    case .notifications: AlertsSettingsTab()
    }
  }
}

#if DEBUG
#Preview("Settings · English · Light") {
  SettingsWindowPreview(language: .english)
    .preferredColorScheme(.light)
}

#Preview("Einstellungen · Deutsch · Dunkel") {
  SettingsWindowPreview(language: .german)
    .preferredColorScheme(.dark)
}

@MainActor
private struct SettingsWindowPreview: View {
  @State private var services: AppServices?
  @State private var container: ModelContainer?
  private let language: AppLanguage

  init(language: AppLanguage) {
    self.language = language
    _services = State(initialValue: UserDefaults(suiteName: "io.octorunner.preview.settings.\(language.rawValue)").map {
      AppServices(
        preferences: AppPreferencesStore(defaults: $0),
        loginService: PreviewLoginItem(),
        notificationClient: PreviewNotificationClient()
      )
    })
    let container = try? OctoRunnerPersistence.makeInMemoryContainer()
    if let container, let scope = URL(string: "https://github.com/example/build") {
      container.mainContext.insert(RunnerEntity(
        name: "Preview Runner", scopeUrl: scope,
        workDirectory: URL(filePath: "/tmp/octorunner-preview/_work"), runnerVersion: "2.0.0",
        executionMode: .external
      ))
    }
    _container = State(initialValue: container)
  }

  var body: some View {
    if let services, let container {
      SettingsWindowView(accountSession: services.accounts)
        .modelContainer(container)
        .environment(services.preferences)
        .environment(services.integration)
        .environment(services.notifications)
        .environment(services.storageMaintenance)
        .environment(\.locale, language.locale)
        .frame(width: 740, height: 650)
    } else {
      Text(verbatim: "Could not create the preview data.")
    }
  }
}

private struct PreviewLoginItem: LoginItemServicing {
  func status() async -> LoginItemState { .unavailable }
  func setEnabled(_ enabled: Bool) async throws {}
}

private struct PreviewNotificationClient: AppNotificationClient {
  func authorizationStatus() async -> NotificationAuthorizationState { .notDetermined }
  func requestAuthorization() async throws -> Bool { false }
  func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) async throws {}
}
#endif
