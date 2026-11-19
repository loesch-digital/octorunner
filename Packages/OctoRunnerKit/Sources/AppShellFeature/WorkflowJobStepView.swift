import CoreModels
import DesignSystem
import SwiftUI

struct WorkflowJobStepView: View {
    @Environment(\.locale) private var locale
    let step: WorkflowJobStep

    var body: some View {
        let display = WorkflowStepPresentation(step: step, locale: locale)
        HStack(alignment: .top, spacing: 10) {
            Text("\(step.number)").monospacedDigit().foregroundStyle(OctoTheme.secondaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.name).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Label(display.title, systemImage: display.symbol).font(.caption).foregroundStyle(color(display.symbol))
            }
            Spacer(minLength: 8)
            Text(step.durationSeconds.map { Duration.seconds($0).formatted(.time(pattern: .minuteSecond)) } ?? "—")
                .font(.caption.monospacedDigit())
        }.padding(.vertical, 5)
    }

    private func color(_ symbol: String) -> Color {
        switch symbol {
        case "play.circle.fill": OctoTheme.accentBlue
        case "xmark.circle.fill": OctoTheme.errorRed
        case "checkmark.circle.fill": OctoTheme.onlineGreen
        case "clock": OctoTheme.warningOrange
        default: OctoTheme.secondaryText
        }
    }
}
