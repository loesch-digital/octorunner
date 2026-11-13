import CoreModels
import DesignSystem
import SwiftUI

struct AuditEventDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let event: AuditEventSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(event.title).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                    AuditEventRow(event: event)
                    Text(event.summary).frame(maxWidth: .infinity, alignment: .leading)
                    LabeledContent { Text(event.id.uuidString).font(.caption.monospaced()) } label: { Text("Event ID", bundle: .module) }
                    LabeledContent {
                        Text(LocalizedStringKey(AuditEventCategory(rawValue: event.category)?.displayTitle ?? event.category), bundle: .module)
                    } label: { Text("Category", bundle: .module) }
                    if let runner = event.targetRunnerName {
                        LabeledContent { Text(runner) } label: { Text("Runner", bundle: .module) }
                    }
                    if let account = event.actorAccountLogin {
                        LabeledContent { Text(account) } label: { Text("Account", bundle: .module) }
                    }
                    if let previous = event.previousValue {
                        valueBlock("Previous value", value: previous)
                    }
                    if let next = event.newValue {
                        valueBlock("New value", value: next)
                    }
                }
                .textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("Close", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Close", bundle: .module))
                    .accessibilityHint(Text("Return to the audit event list.", bundle: .module))
            }
        }
        .padding(24).frame(minWidth: 560, idealWidth: 700, minHeight: 400, idealHeight: 560)
        .background(OctoTheme.surfaceLowest)
    }

    private func valueBlock(_ title: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title, bundle: .module).font(.headline)
            Text(value).font(.body.monospaced()).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding().background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }
}
