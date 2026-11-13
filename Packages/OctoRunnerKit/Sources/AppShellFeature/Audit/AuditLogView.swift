import CoreModels
import DesignSystem
import SwiftUI

public struct AuditLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var filter = AuditLogFilter()
    @State private var pageSize = 200

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label { Text("Audit Log", bundle: .module) } icon: { Image(systemName: "clock.arrow.circlepath").accessibilityHidden(true) }
                    .font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: { Text("Close", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Close", bundle: .module))
                    .accessibilityHint(Text("Close the audit log.", bundle: .module))
            }
            Text("Local app and runner events, newest first. Filters and search apply to stored history.", bundle: .module)
                .foregroundStyle(OctoTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            HStack {
                Picker(selection: $filter.category) {
                    Text("All categories", bundle: .module).tag(Optional<AuditEventCategory>.none)
                    ForEach(AuditEventCategory.allCases) { category in
                        Text(LocalizedStringKey(category.displayTitle), bundle: .module).tag(Optional(category))
                    }
                } label: { Text("Category", bundle: .module) }
                .accessibilityLabel(Text("Category", bundle: .module))
                .accessibilityHint(Text("Filter events by category.", bundle: .module))
                Picker(selection: $filter.severity) {
                    Text("All severities", bundle: .module).tag(Optional<AuditEventSeverity>.none)
                    ForEach(AuditEventSeverity.allCases) { severity in
                        Text(LocalizedStringKey(severity.badgeTitle), bundle: .module).tag(Optional(severity))
                    }
                } label: { Text("Severity", bundle: .module) }
                .accessibilityLabel(Text("Severity", bundle: .module))
                .accessibilityHint(Text("Filter events by severity.", bundle: .module))
            }
            HStack {
                TextField(text: Binding(get: { filter.runnerName ?? "" }, set: { filter.runnerName = $0 })) {
                    Text("Runner name (exact)", bundle: .module)
                }
                .accessibilityLabel(Text("Runner name (exact)", bundle: .module))
                .accessibilityHint(Text("Leave empty for all runners, including removed runners.", bundle: .module))
                TextField(text: $filter.search) { Text("Search event titles and details", bundle: .module) }
                    .accessibilityLabel(Text("Search event titles and details", bundle: .module))
                    .accessibilityHint(Text("Search the full stored history without changing events.", bundle: .module))
                Button { filter = AuditLogFilter() } label: { Text("Reset filters", bundle: .module) }
                    .accessibilityLabel(Text("Reset filters", bundle: .module))
                    .accessibilityHint(Text("Show events from all categories, severities and runners.", bundle: .module))
            }
            AuditLogResultsView(filter: filter, pageSize: pageSize) { pageSize += 200 }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(minWidth: 680, idealWidth: 960, minHeight: 520, idealHeight: 680)
        .background(OctoTheme.surfaceLowest)
        .onChange(of: filter) { pageSize = 200 }
    }
}
