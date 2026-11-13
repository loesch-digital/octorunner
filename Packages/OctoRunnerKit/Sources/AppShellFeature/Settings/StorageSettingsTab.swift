import CoreModels
import DesignSystem
import RunnerEngine
import SwiftData
import SwiftUI

public struct StorageSettingsTab: View {
    @Environment(AppPreferencesStore.self) private var preferences
    @Environment(StorageMaintenanceController.self) private var maintenance
    @Environment(\.modelContext) private var context
    @State private var operation: Task<Void, Never>?
    @State private var showPreview = false
    @State private var preview: StorageUsageSnapshot?

    public init() {}

    public var body: some View {
        @Bindable var preferences = preferences
        SettingsPage("Cache & Storage", subtitle: "Measure managed runner storage and safely remove old data.") {
            SettingsCard("Storage overview", symbol: "externaldrive", subtitle: "Analysis starts only when requested or when automatic cleanup is enabled.") {
                if let snapshot = maintenance.snapshot {
                    ForEach(["workspaces", "actions", "temporary", "logs"], id: \.self) { category in
                        LabeledContent {
                            Text((snapshot.logicalBytesByCategory[category] ?? 0), format: .byteCount(style: .file))
                        } label: { Text(categoryTitle(category), bundle: .module) }
                    }
                    if let volume = maintenance.volume {
                        LabeledContent { Text(volume.availableBytes, format: .byteCount(style: .file)) }
                            label: { Text("Available volume capacity", bundle: .module) }
                    }
                    Text(snapshot.observedAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption).foregroundStyle(OctoTheme.secondaryText)
                }
                HStack {
                    Button { analyze() } label: { Text("Analyze storage", bundle: .module) }
                        .accessibilityLabel(Text("Analyze storage", bundle: .module))
                        .accessibilityHint(Text("Measure only OctoRunner-managed runner folders.", bundle: .module))
                        .disabled(maintenance.isBusy)
                    Button {
                        preview = maintenance.snapshot
                        showPreview = true
                    } label: { Text("Review cleanup…", bundle: .module) }
                        .accessibilityLabel(Text("Review cleanup…", bundle: .module))
                        .accessibilityHint(Text("Preview old items before confirming deletion.", bundle: .module))
                        .disabled(maintenance.isBusy || maintenance.snapshot?.candidates.isEmpty != false)
                    if maintenance.isBusy { ProgressView().controlSize(.small).accessibilityLabel(Text("Analyzing or cleaning storage", bundle: .module)) }
                }
                Text("Sizes are logical file sizes. APFS sharing and snapshots can change the space actually reclaimed.", bundle: .module)
                    .font(.callout).foregroundStyle(OctoTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
                if maintenance.wasInterrupted {
                    Text("Cleanup was interrupted and may be partial. Analyze storage again; the attempt is recorded in the audit log.", bundle: .module)
                        .foregroundStyle(OctoTheme.warningOrange).fixedSize(horizontal: false, vertical: true)
                }
                if maintenance.failed {
                    Label { Text("Storage operation stopped. Analyze again before retrying; some items may already have been removed.", bundle: .module) }
                        icon: { Image(systemName: "exclamationmark.triangle").accessibilityHidden(true) }
                        .foregroundStyle(OctoTheme.errorRed).fixedSize(horizontal: false, vertical: true)
                }
                if let report = maintenance.lastReport {
                    LabeledContent { Text(report.removedCount, format: .number) } label: { Text("Items removed", bundle: .module) }
                    LabeledContent { Text(report.skippedCount, format: .number) } label: { Text("Items skipped", bundle: .module) }
                }
            }
            SettingsCard("Cleanup policy", symbol: "slider.horizontal.3", subtitle: "Automatic cleanup checks every ten minutes while OctoRunner is open.") {
                Picker(selection: $preferences.storagePolicy.pruningMode) {
                    Text("Manual only", bundle: .module).tag(WorkspacePruningMode.manual)
                    Text("Remove old data automatically", bundle: .module).tag(WorkspacePruningMode.olderThanDays)
                    Text("Only when disk space is low", bundle: .module).tag(WorkspacePruningMode.lowDiskSpace)
                } label: { Text("Cleanup policy", bundle: .module) }
                .accessibilityLabel(Text("Cleanup policy", bundle: .module))
                .accessibilityHint(Text("Manual mode never schedules a cleanup.", bundle: .module))
                Stepper(value: $preferences.pruneWorkspacesOlderThanDays, in: 1...365) {
                    LabeledContent { Text(preferences.pruneWorkspacesOlderThanDays, format: .number) } label: { Text("Workspace age (days)", bundle: .module) }
                }
                .accessibilityLabel(Text("Workspace age (days)", bundle: .module))
                .accessibilityHint(Text("Keep workspaces with files modified more recently than this limit.", bundle: .module))
                Picker(selection: $preferences.storagePolicy.logRetentionDays) {
                    ForEach([7, 14, 30, 90], id: \.self) { Text($0, format: .number).tag($0) }
                } label: { Text("Log retention (days)", bundle: .module) }
                .accessibilityLabel(Text("Log retention (days)", bundle: .module))
                .accessibilityHint(Text("Always keep the newest runner diagnostic log.", bundle: .module))
                Stepper(value: $preferences.storagePolicy.minimumFreeSpaceGB, in: 1...1_000) {
                    LabeledContent { Text(preferences.storagePolicy.minimumFreeSpaceGB, format: .number) } label: { Text("Minimum free space (GB)", bundle: .module) }
                }
                .disabled(preferences.storagePolicy.pruningMode != .lowDiskSpace)
                .accessibilityLabel(Text("Minimum free space (GB)", bundle: .module))
                .accessibilityHint(Text("Stop automatic cleanup when this much volume capacity is available.", bundle: .module))
            }
            Text("Cleanup requires an unloaded LaunchAgent and no listener or worker process. Imported runners, tool caches, configuration, binaries and external Xcode caches are excluded. launchd output logs are retained.", bundle: .module)
                .font(.callout).foregroundStyle(OctoTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
        }
        .sheet(isPresented: $showPreview) {
            if let preview {
                StorageCleanupPreview(snapshot: preview) {
                    showPreview = false
                    operation?.cancel()
                    operation = Task {
                        await maintenance.clean(in: context, candidateSnapshot: preview)
                        guard !Task.isCancelled else { return }
                        await maintenance.refresh(in: context)
                    }
                }
            }
        }
        .onDisappear { operation?.cancel() }
    }

    private func analyze() {
        operation?.cancel()
        operation = Task { await maintenance.refresh(in: context) }
    }

    private func categoryTitle(_ category: String) -> LocalizedStringKey {
        switch category {
        case "actions": "Actions cache"
        case "temporary": "Temporary files"
        case "logs": "Diagnostic logs"
        default: "Workspaces and tools"
        }
    }
}
