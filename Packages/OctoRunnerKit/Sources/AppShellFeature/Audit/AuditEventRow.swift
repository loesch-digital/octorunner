import CoreModels
import DesignSystem
import SwiftUI

struct AuditEventRow: View {
    let event: AuditEventSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text(LocalizedStringKey(event.severity.uppercased()), bundle: .module)
                } icon: {
                    Image(systemName: event.severity == "critical" ? "xmark.octagon" : event.severity == "warning" ? "exclamationmark.triangle" : "info.circle")
                        .accessibilityHidden(true)
                }
                .font(.caption.bold())
                .foregroundStyle(event.severity == "critical" ? OctoTheme.errorRed : event.severity == "warning" ? OctoTheme.warningOrange : OctoTheme.secondaryText)
                Spacer()
                Text(event.timestamp, format: .dateTime.year().month().day().hour().minute().second())
                    .font(.caption).foregroundStyle(OctoTheme.secondaryText)
            }
            Text(event.title).font(.headline).lineLimit(2)
            Text(event.summary).font(.callout).foregroundStyle(OctoTheme.secondaryText).lineLimit(2)
            if let name = event.targetRunnerName { Text(name).font(.caption.monospaced()) }
        }
        .padding(.vertical, 8)
    }
}
