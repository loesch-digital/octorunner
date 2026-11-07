import CoreModels
import DesignSystem
import SwiftData
import SwiftUI
import TelemetryKit

public struct MainShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]

    @State private var selectedSection: SidebarSection? = .allRunners
    @State private var searchText: String = ""
    @State private var hostSnapshot: HostTelemetrySnapshot?
    private let telemetryActor = HostTelemetryActor()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 280)
        } detail: {
            detailContent
        }
        .navigationTitle("OctoRunner")
        .searchable(text: $searchText, prompt: "Search runners, labels...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Seed Demo Runner", systemImage: "sparkles", action: seedDemoRunnerIfEmpty)
                Button("New Runner", systemImage: "plus", action: seedDemoRunnerIfEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(OctoTheme.accentBlue)
            }
        }
        .safeAreaInset(edge: .bottom) {
            statusFooterBar
        }
        .task {
            hostSnapshot = await telemetryActor.currentSnapshot()
        }
    }

    private var sidebarContent: some View {
        List(selection: $selectedSection) {
            Section("RUNNER STATUS") {
                ForEach(SidebarSection.allCases) { section in
                    HStack {
                        Label(section.title, systemImage: section.systemImage)
                        Spacer()
                        Text("\(count(for: section))")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .tag(section)
                }
            }
        }
        .listStyle(.sidebar)
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                kpiHeaderRow
                runnerListCard
            }
            .padding(20)
        }
        .background(OctoTheme.surfaceLowest)
    }

    private var kpiHeaderRow: some View {
        HStack(spacing: 12) {
            kpiCard(
                title: "Running Instances",
                value: "\(runners.count(where: { $0.status == .idle || $0.status == .busy })) of \(runners.count) active",
                subtitle: "Supervised by OctoRunner Process Actor",
                accent: OctoTheme.onlineGreen
            )
            kpiCard(
                title: "Host CPU Architecture",
                value: hostSnapshot?.cpuSummary ?? "Apple Silicon",
                subtitle: "\(hostSnapshot?.totalCoreCount ?? 12) Cores active",
                accent: OctoTheme.accentBlue
            )
            kpiCard(
                title: "Unified Memory",
                value: "\(String(format: "%.0f", hostSnapshot?.physicalMemoryGB ?? 32)) GB RAM",
                subtitle: "Pressure: Nominal",
                accent: OctoTheme.onlineGreen
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.outlineVariant.opacity(0.45), lineWidth: 1)
        }
    }

    private var runnerListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Registered Runner Pool")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("v0.1.0 Infrastructure Ready")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if filteredRunners.isEmpty {
                ContentUnavailableView {
                    Label("No Runners Registered Yet", systemImage: "server.rack")
                } description: {
                    Text("Click 'New Runner' in the toolbar to test SwiftData persistence in v0.1.0.")
                } actions: {
                    Button("Add Demo Runner Instance", systemImage: "plus.circle.fill", action: seedDemoRunnerIfEmpty)
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ForEach(filteredRunners) { runner in
                    runnerRow(runner)
                }
            }
        }
        .padding(16)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.outlineVariant.opacity(0.45), lineWidth: 1)
        }
    }

    private func runnerRow(_ runner: RunnerEntity) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "terminal.fill")
                .font(.system(size: 16))
                .foregroundStyle(OctoTheme.accentBlue)
                .frame(width: 32, height: 32)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(runner.name)
                        .font(.system(size: 13, weight: .semibold))
                    RunnerStatusBadge(status: runner.status)
                }
                Text(runner.scopeUrlString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 6) {
                ForEach(runner.labels, id: \.self) { label in
                    Text(label)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(OctoTheme.surfaceHighest, in: .rect(cornerRadius: 4))
                }
            }

            Button("Remove", systemImage: "trash", role: .destructive) {
                deleteRunner(runner)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 8))
    }

    private var statusFooterBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(OctoTheme.onlineGreen)
                    .frame(width: 7, height: 7)
                Text("supervisor: active")
                    .font(.system(size: 11, design: .monospaced))
            }
            Spacer()
            Text("\(hostSnapshot?.cpuSummary ?? "Apple Silicon") • \(String(format: "%.0f", hostSnapshot?.physicalMemoryGB ?? 32)) GB Unified RAM")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(OctoTheme.surface)
    }

    private var filteredRunners: [RunnerEntity] {
        runners.filter { runner in
            let matchesSection: Bool = switch selectedSection ?? .allRunners {
            case .allRunners, .queueWorkpools, .launchdSettings:
                true
            case .activeDaemons:
                runner.status == .idle || runner.status == .busy
            case .failedFaulted:
                runner.status == .faulted
            }
            guard matchesSection else { return false }
            if searchText.isEmpty { return true }
            return runner.name.localizedStandardContains(searchText)
                || runner.labels.contains { $0.localizedStandardContains(searchText) }
        }
    }

    private func count(for section: SidebarSection) -> Int {
        switch section {
        case .allRunners, .queueWorkpools, .launchdSettings:
            return runners.count
        case .activeDaemons:
            return runners.count(where: { $0.status == .idle || $0.status == .busy })
        case .failedFaulted:
            return runners.count(where: { $0.status == .faulted })
        }
    }

    private func seedDemoRunnerIfEmpty() {
        let index = runners.count + 1
        let runner = RunnerEntity(
            name: "mac-runner-\(index)",
            scopeType: .repository,
            scopeUrl: URL(string: "https://github.com/loesch-digital/octorunner")!,
            status: index.isMultiple(of: 2) ? .busy : .idle,
            labels: ["self-hosted", "macos", "arm64", "xcode-27"],
            workDirectory: URL(fileURLWithPath: NSHomeDirectory()).appending(path: "actions-runner/_work"),
            pid: Int32(4800 + index)
        )
        modelContext.insert(runner)
        try? modelContext.save()
    }

    private func deleteRunner(_ runner: RunnerEntity) {
        modelContext.delete(runner)
        try? modelContext.save()
    }
}
