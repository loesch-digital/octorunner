import Foundation
import TelemetryKit

/// Shared status wording for the cards and their accessible text.
enum HostTelemetryStatusText {
    static func memoryPressure(_ value: HostMemoryPressure?, locale: Locale) -> String {
        let key: String.LocalizationValue
        switch value {
        case .normal: key = "Normal"
        case .warning: key = "Elevated"
        case .critical: key = "Critical"
        case nil: key = "Unavailable"
        }
        return AppLocalization.string(key, locale: locale)
    }

    static func thermalState(_ value: HostThermalState?, locale: Locale) -> String {
        let key: String.LocalizationValue
        switch value {
        case .nominal: key = "Normal"
        case .fair: key = "Slightly elevated"
        case .serious: key = "High"
        case .critical: key = "Critical"
        case nil: key = "Unavailable"
        }
        return AppLocalization.string(key, locale: locale)
    }
}
