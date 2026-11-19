import CoreModels
import Foundation
import DesignSystem
import SwiftUI

struct WorkflowStepPresentation {
    let title: String
    let symbol: String
    var color: Color {
        switch symbol {
        case "play.circle.fill": OctoTheme.accentBlue
        case "xmark.circle.fill": OctoTheme.errorRed
        case "checkmark.circle.fill": OctoTheme.onlineGreen
        case "clock": OctoTheme.warningOrange
        default: OctoTheme.secondaryText
        }
    }

    init(step: WorkflowJobStep, locale: Locale) {
        let key: String.LocalizationValue
        switch (step.status, step.conclusion) {
        case ("completed", "success"): key = "Succeeded"; symbol = "checkmark.circle.fill"
        case ("completed", "failure"), ("completed", "timed_out"), ("completed", "startup_failure"), ("completed", "action_required"), ("completed", "stale"):
            key = "Failed"; symbol = "xmark.circle.fill"
        case ("completed", "cancelled"): key = "Cancelled"; symbol = "slash.circle"
        case ("completed", "skipped"): key = "Skipped"; symbol = "forward.end"
        case ("completed", _): key = "Completed"; symbol = "checkmark.circle"
        case ("in_progress", _): key = "Running"; symbol = "play.circle.fill"
        case ("queued", _), ("waiting", _), ("pending", _): key = "Queued"; symbol = "clock"
        default: key = "Unknown"; symbol = "questionmark.circle"
        }
        title = AppLocalization.string(key, locale: locale)
    }
}
