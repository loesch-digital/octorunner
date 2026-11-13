import Foundation

public enum AppLanguage: String, CaseIterable, Codable, Sendable, Identifiable {
    case system = "system"
    case english = "en"
    case german = "de"

    public var id: String { rawValue }

    public var locale: Locale {
        switch self {
        case .system: .autoupdatingCurrent
        case .english: Locale(identifier: "en")
        case .german: Locale(identifier: "de")
        }
    }

    public var displayTitle: String {
        switch self {
        case .system:
            return "System Default (macOS)"
        case .english:
            return "English (United States)"
        case .german:
            return "Deutsch (Deutschland)"
        }
    }
}
