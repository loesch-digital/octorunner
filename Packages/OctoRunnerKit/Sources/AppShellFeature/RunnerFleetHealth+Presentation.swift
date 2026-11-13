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
        case .unknown: AppLocalization.string("Runner status unknown", locale: locale)
        case .healthy: AppLocalization.string("All local runners active", locale: locale)
        case .busy: AppLocalization.string("Runners running jobs or restarting", locale: locale)
        case .offline: AppLocalization.string("Runner offline", locale: locale)
        case .faulted: AppLocalization.string("Runner error", locale: locale)
        }
    }
}
