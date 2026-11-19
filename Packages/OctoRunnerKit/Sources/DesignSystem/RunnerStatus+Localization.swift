import CoreModels
import Foundation

extension RunnerStatus {
    public func localizedBadgeTitle(locale: Locale) -> String {
        String(localized: LocalizedStringResource(String.LocalizationValue(stringLiteral: badgeTitle),
            locale: locale, bundle: .atURL(Bundle.module.bundleURL)))
    }
}
