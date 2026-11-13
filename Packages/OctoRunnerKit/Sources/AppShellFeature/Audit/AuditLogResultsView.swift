import CoreModels
import DesignSystem
import SwiftData
import SwiftUI

struct AuditLogResultsView: View {
    @Query private var entries: [AuditLogEntity]
    @State private var selected: AuditEventSnapshot?
    @State private var document: AuditExportDocument?
    @State private var isExporting = false
    @State private var exportFailed = false
    let pageSize: Int
    let loadMore: () -> Void

    init(filter: AuditLogFilter, pageSize: Int, loadMore: @escaping () -> Void) {
        _entries = Query(filter.descriptor(limit: pageSize + 1))
        self.pageSize = pageSize
        self.loadMore = loadMore
    }

    var body: some View {
        VStack(spacing: 12) {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label { Text("No matching audit events", bundle: .module) } icon: { Image(systemName: "clock.arrow.circlepath") }
                } description: {
                    Text("New events appear here automatically. Try changing the filters.", bundle: .module)
                }
            } else {
                List {
                    ForEach(entries.prefix(pageSize)) { entry in
                        Button { selected = AuditEventSnapshot(entry) } label: {
                            AuditEventRow(event: AuditEventSnapshot(entry))
                                .frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(entry.title))
                        .accessibilityValue(entry.targetRunnerName.map { Text(verbatim: $0) } ?? Text("App-wide event", bundle: .module))
                        .accessibilityHint(Text("Open the full event details and before/after values.", bundle: .module))
                    }
                    if entries.count > pageSize {
                        Button(action: loadMore) { Text("Load more events", bundle: .module) }
                            .accessibilityLabel(Text("Load more events", bundle: .module))
                            .accessibilityHint(Text("Load the next 200 matching events.", bundle: .module))
                    }
                }
                .listStyle(.inset)
            }
            HStack {
                LabeledContent { Text(min(entries.count, pageSize), format: .number) } label: { Text("Shown events", bundle: .module) }
                Spacer()
                Button {
                    do {
                        document = try AuditExportDocument(events: entries.prefix(pageSize).map(AuditEventSnapshot.init))
                        exportFailed = false; isExporting = true
                    } catch { exportFailed = true }
                } label: { Label { Text("Export shown events…", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") } }
                .disabled(entries.isEmpty)
                .accessibilityLabel(Text("Export shown events…", bundle: .module))
                .accessibilityHint(Text("Save the currently shown events as a JSON file. Load more to include older events.", bundle: .module))
            }
            if exportFailed {
                Label { Text("The audit export could not be saved. Try another location.", bundle: .module) }
                    icon: { Image(systemName: "exclamationmark.triangle").accessibilityHidden(true) }
                    .foregroundStyle(OctoTheme.errorRed)
            }
        }
        .sheet(item: $selected) { event in AuditEventDetailView(event: event) }
        .fileExporter(isPresented: $isExporting, document: document, contentTypes: [.json], defaultFilename: "OctoRunner-audit", onCompletion: { result in
            if case .failure(let error) = result {
                let cocoa = error as NSError
                exportFailed = !(cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSUserCancelledError)
            }
        }, onCancellation: { exportFailed = false })
    }
}
