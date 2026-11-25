import CoreModels
import DesignSystem
import SwiftUI

struct WorkflowJobStepView: View {
    @Environment(\.locale) private var locale
    let step: WorkflowJobStep
    var now: Date? = nil

    var body: some View {
        let display = WorkflowStepPresentation(step: step, locale: locale)
        HStack(alignment: .top, spacing: 10) {
            Text("\(step.number)").monospacedDigit().foregroundStyle(OctoTheme.secondaryText)
            VStack(alignment: .leading, spacing: 4) {
                Text(step.name).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                Label(display.title, systemImage: display.symbol).font(.caption).foregroundStyle(display.color)
            }
            Spacer(minLength: 8)
            Text(WorkflowHistoryPresentation.duration(step.elapsedDuration(at: now)))
                .font(.caption.monospacedDigit())
        }.padding(.vertical, 5)
    }

}
