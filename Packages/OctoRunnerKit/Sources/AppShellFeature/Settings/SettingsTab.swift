import SwiftUI

enum SettingsTab: String, Hashable, CaseIterable {
  case general
  case background
  case failover
  case storage
  case auth
  case notifications

  var title: LocalizedStringKey {
    switch self {
    case .general: "General"
    case .background: "Autostart & Background"
    case .failover: "Failover"
    case .storage: "Cache & Storage"
    case .auth: "Auth & Tokens"
    case .notifications: "Notifications"
    }
  }

  var systemImage: String {
    switch self {
    case .general: "gearshape"
    case .background: "power"
    case .failover: "arrow.clockwise"
    case .storage: "externaldrive"
    case .auth: "key"
    case .notifications: "bell"
    }
  }
}

extension SettingsTab {
  static func matching(_ query: String, locale: Locale) -> [Self] {
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return allCases }
    return allCases.filter { tab in
      let text = tab.searchKeys.map { AppLocalization.string($0, locale: locale) }.joined(
        separator: " ")
      return words.allSatisfy {
        text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
          != nil
      }
    }
  }

  private var searchKeys: [String.LocalizationValue] {
    switch self {
    case .general:
      [
        "General", "System integration", "Show icon in menu bar",
        "Hide Dock icon when windows are closed", "Language",
      ]
    case .background:
      [
        "Autostart & Background", "Launch at macOS login", "Runner SHELL environment",
        "Inherit OctoRunner's PATH",
      ]
    case .failover:
      ["Failover", "Restart policy", "Restart delay (seconds)"]
    case .storage:
      ["Cache & Storage", "Workspace age (days)", "Log retention (days)", "Cleanup policy"]
    case .auth:
      [
        "Auth & Tokens", "Connected GitHub accounts", "Credential security",
        "Credentials are stored only in macOS Keychain.",
      ]
    case .notifications:
      [
        "Notifications", "Enable macOS notifications", "Play notification sounds",
        "Runner comes online", "Runner goes offline", "Runner enters an error state",
        "Local workflow job fails", "Low disk space",
      ]
    }
  }
}
