import CoreModels
import DesignSystem
import SwiftUI

public struct DashboardRunnerRow: View {
    let runner: RunnerEntity
    let lastJob: WorkflowHistoryEntry?
    let openLog: () -> Void
    let openSettings: () -> Void
    let migrate: () -> Void
    let remove: () -> Void

    public init(runner: RunnerEntity, lastJob: WorkflowHistoryEntry? = nil, openLog: @escaping () -> Void, openSettings: @escaping () -> Void,
                migrate: @escaping () -> Void, remove: @escaping () -> Void) {
        self.runner = runner
        self.lastJob = lastJob
        self.openLog = openLog
        self.openSettings = openSettings
        self.migrate = migrate
        self.remove = remove
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(runner.name)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(runner.name)
                    Text(runner.scopeUrlString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(runner.scopeUrlString)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Button(action: openLog) {
                    Label { Text("Live Log", bundle: .module) } icon: { Image(systemName: "apple.terminal") }
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Live Log", bundle: .module))
                .accessibilityHint(Text("Opens the selected runner’s console log", bundle: .module))

                Menu {
                    Button(action: openSettings) {
                        Label { Text("Runner Settings", bundle: .module) } icon: { Image(systemName: "slider.horizontal.3") }
                    }
                    .accessibilityHint(Text("Opens configuration for this runner", bundle: .module))
                    if runner.isImportedLocal {
                        Button(action: migrate) {
                            Label { Text("Migrate Runner", bundle: .module) } icon: { Image(systemName: "arrow.right.doc.on.clipboard") }
                        }
                        .accessibilityHint(Text("Moves the runner into OctoRunner’s managed folder and enables autostart", bundle: .module))
                    }
                    Button(role: .destructive, action: remove) {
                        Label { Text("Remove Runner", bundle: .module) } icon: { Image(systemName: "trash") }
                    }
                    .accessibilityHint(Text("Removes this runner from the local list", bundle: .module))
                } label: {
                    Label { Text("Runner Actions", bundle: .module) } icon: { Image(systemName: "ellipsis.circle") }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityHint(Text("Shows settings, migration and removal actions", bundle: .module))
            }

            HStack(spacing: 8) {
                RunnerStatusBadge(status: runner.status)
                    .fixedSize()
                Text(runner.isImportedLocal ? String(localized: "Imported", bundle: .module) : String(localized: "Managed", bundle: .module))
                    .lineLimit(1)
                if let version = runner.runnerVersion {
                    Text("v\(version)").lineLimit(1).truncationMode(.middle)
                }
                if let pid = runner.pid { Text("PID \(String(pid))").lineLimit(1) }
            }
            .font(.caption.monospaced())
            .foregroundStyle(.secondary)

            Divider()
            RunnerLastJobView(entry: lastJob)

            if !runner.labels.isEmpty {
                Text(runner.labels.joined(separator: " · "))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(runner.labels.joined(separator: ", "))
                    .accessibilityLabel("Labels: \(runner.labels.joined(separator: ", "))")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Runner \(runner.name)")
    }
}
