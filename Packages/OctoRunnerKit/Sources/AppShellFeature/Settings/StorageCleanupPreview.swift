import DesignSystem
import RunnerEngine
import SwiftUI

struct StorageCleanupPreview: View {
    @Environment(\.dismiss) private var dismiss
    let snapshot: StorageUsageSnapshot
    let confirm: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Review cleanup", bundle: .module).font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("These old items may be deleted permanently. Active, loaded or changed runners are skipped after another safety check. Runner IDs identify their managed folder.", bundle: .module)
                .foregroundStyle(OctoTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            List(snapshot.candidates) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.relativePath).font(.body.monospaced()).textSelection(.enabled)
                    Text(item.runnerID.uuidString).font(.caption).foregroundStyle(OctoTheme.secondaryText)
                    Text(item.logicalBytes, format: .byteCount(style: .file)).font(.caption)
                }
            }
            HStack {
                Spacer()
                Button { dismiss() } label: { Text("Cancel", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Cancel", bundle: .module))
                    .accessibilityHint(Text("Close without deleting files.", bundle: .module))
                Button(role: .destructive, action: confirm) { Text("Delete eligible items", bundle: .module) }
                    .disabled(snapshot.candidates.isEmpty)
                    .accessibilityLabel(Text("Delete eligible items", bundle: .module))
                    .accessibilityHint(Text("Permanently delete only the reviewed items that still pass all checks.", bundle: .module))
            }
        }
        .padding(24).frame(minWidth: 520, idealWidth: 620, minHeight: 360, idealHeight: 480)
    }
}
