import SwiftUI

enum SettingsTab: Hashable, CaseIterable {
    case general
    case background
    case failover
    case auth
    case notifications

    var title: LocalizedStringKey {
        switch self {
        case .general: "General"
        case .background: "Autostart & Background"
        case .failover: "Failover"
        case .auth: "Auth & Tokens"
        case .notifications: "Notifications"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .background: "power"
        case .failover: "arrow.clockwise"
        case .auth: "key"
        case .notifications: "bell"
        }
    }
}
