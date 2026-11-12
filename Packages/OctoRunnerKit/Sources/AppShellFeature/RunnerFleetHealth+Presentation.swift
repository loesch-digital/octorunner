import Foundation

extension RunnerFleetHealth {
    public var symbolName: String {
        switch self {
        case .unknown: "questionmark.circle"
        case .healthy: "checkmark.circle.fill"
        case .busy: "arrow.triangle.2.circlepath.circle.fill"
        case .offline: "pause.circle.fill"
        case .faulted: "exclamationmark.octagon.fill"
        }
    }

    public func localizedTitle(locale: Locale) -> String {
        switch self {
        case .unknown: String(localized: "Runner status unknown", bundle: .module, locale: locale)
        case .healthy: String(localized: "All local runners active", bundle: .module, locale: locale)
        case .busy: String(localized: "Runners busy or restarting", bundle: .module, locale: locale)
        case .offline: String(localized: "Runner offline", bundle: .module, locale: locale)
        case .faulted: String(localized: "Runner error", bundle: .module, locale: locale)
        }
    }
}
