import CoreModels
import DesignSystem
import SwiftUI
import TelemetryKit

struct DashboardRunnerPool<Row: View>: View {
    @Environment(\.locale) private var locale

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.usesDashboardSampleData) private var usesDashboardSampleData
    @State private var resourceUsage: [UUID: RunnerResourceUsage] = [:]

    let runners: [RunnerEntity]
    let registeredCount: Int
    let section: SidebarSection
    let searchText: String
    let jobResults: LocalJobResults
    let isSyncingRunners: Bool
    let syncRunners: () -> Void
    let importRunner: () -> Void
    @ViewBuilder let runnerRow: (RunnerEntity, RunnerResourceUsage?) -> Row

    var body: some View {
        let targets = processTargets
        VStack(alignment: .leading, spacing: 12) {
            if !jobResults.unreviewedFailures.isEmpty { JobFailureNotice(results: jobResults) }
            HStack {
                Text(AppLocalization.string("Registered Runner Pool", locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(AppLocalization.string("Instances: \(runners.count)", locale: locale))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if runners.isEmpty {
                emptyContent
            } else {
                ForEach(runners) { runner in
                    runnerRow(runner, resourceUsage[runner.id])
                }
            }
        }
        .padding(16)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.outlineVariant.opacity(0.45), lineWidth: 1)
        }
        .task(id: targets) { await sampleResources(for: targets) }
    }

    private var processTargets: [RunnerProcessTarget] {
        guard scenePhase == .active, !usesDashboardSampleData else { return [] }
        return runners.compactMap { runner in
            guard let root = runner.rootDirectoryPath, !root.isEmpty else { return nil }
            return RunnerProcessTarget(id: runner.id, name: runner.name, rootPath: root)
        }
    }

    private func sampleResources(for targets: [RunnerProcessTarget]) async {
        guard !Task.isCancelled else { return }
        resourceUsage = [:]
        guard !targets.isEmpty else { return }
        let monitor = RunnerProcessMonitor()
        while !Task.isCancelled {
            let processes = try? await monitor.snapshot(targets: targets)
            guard !Task.isCancelled else { return }
            resourceUsage = RunnerResourceUsage.byRunner(processes ?? [])
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        let emptyState = RunnerPoolEmptyState(registeredCount: registeredCount, section: section, search: searchText)
        if emptyState != .unregistered {
            ContentUnavailableView {
                switch emptyState {
                case .noFaulted:
                    Label { Text("No failed or faulted runners", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
                case .noActive:
                    Label { Text("No active runners", bundle: .module) } icon: { Image(systemName: "pause.circle") }
                case .noSearchMatches, .unregistered:
                    Label { Text("No matching runners", bundle: .module) } icon: { Image(systemName: "magnifyingglass") }
                }
            } description: {
                Text("Your runners are still registered. Choose All Runners or change the search to see them.", bundle: .module)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            ContentUnavailableView {
                Label(AppLocalization.string("No Runners Registered Yet", locale: locale), systemImage: "server.rack")
            } description: {
                Text(AppLocalization.string("Click 'Sync Runners' to auto-import local runners or 'New Runner' to register a new instance.", locale: locale))
            } actions: {
                HStack(spacing: 10) {
                    Button(AppLocalization.string("Sync Local & GitHub Runners", locale: locale), systemImage: "arrow.triangle.2.circlepath", action: syncRunners)
                    .buttonStyle(.borderedProminent)
                    .disabled(isSyncingRunners)

                    Button(AppLocalization.string("Import Runner Folder…", locale: locale), systemImage: "folder.badge.plus", action: importRunner)
                        .buttonStyle(.bordered)
                        .disabled(isSyncingRunners)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        }
    }
}
