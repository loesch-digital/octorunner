import AppKit
import DesignSystem
import SwiftUI

struct WorkflowHistoryErrorBanner: View {
    let message: String
    @State private var copiedMessage: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(OctoTheme.warningOrange)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(verbatim: message)
                    .foregroundStyle(OctoTheme.warningOrange)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button {
                        if copy(to: .general) { copiedMessage = message }
                    } label: {
                        Label {
                            Text("Copy error details", bundle: .module)
                        } icon: {
                            Image(systemName: "doc.on.doc")
                        }
                    }
                    .accessibilityHint(Text("Copies the full workflow history warning to the clipboard", bundle: .module))
                    if copiedMessage == message {
                        Text("Copied", bundle: .module)
                            .foregroundStyle(OctoTheme.secondaryText)
                    }
                }
            }
        }
        .font(.callout)
    }

    func copy(to pasteboard: NSPasteboard) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(message, forType: .string)
    }
}
