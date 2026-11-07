import AppKit
import CoreModels
import DesignSystem
import RunnerEngine
import SwiftUI

public enum RunnerConsoleLogTab: String, CaseIterable, Identifiable, Sendable {
    case liveJobOutput = "Live Job Output"
    case serviceLog = "Background Service Log"
    case environmentVariables = "Environment Variables"
    case diagnostics = "Runner Diagnostics"

    public var id: String { rawValue }
}

public struct RunnerConsoleLogSheet: View {
    @Environment(\.dismiss) private var dismiss
    public let runner: RunnerEntity

    @State private var selectedTab: RunnerConsoleLogTab = .liveJobOutput
    @State private var logLines: [RunnerLogLine] = []
    @State private var filterText: String = ""
    @State private var autoScroll: Bool = true
    @State private var isLoading: Bool = false

    private let logStreamer = RunnerLogStreamerActor()

    public init(runner: RunnerEntity) {
        self.runner = runner
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(18)
                .background(OctoTheme.surface)

            Divider()

            tabBarSection
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(OctoTheme.surfaceLow)

            Divider()

            terminalContentSection
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            footerSection
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .background(OctoTheme.surface)
        }
        .frame(width: 820, height: 600)
        .background(OctoTheme.surfaceLowest)
        .task {
            await reloadLogs()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "apple.terminal.fill")
                .font(.system(size: 24))
                .foregroundStyle(OctoTheme.accentBlue)
                .frame(width: 44, height: 44)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(runner.name)
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                    RunnerStatusBadge(status: runner.status)
                    if let pid = runner.pid {
                        Text("PID \(String(pid))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let version = runner.runnerVersion {
                        Text("v\(version)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(runner.scopeUrlString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(OctoTheme.accentBlue)

                HStack(spacing: 6) {
                    ForEach(runner.labels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(OctoTheme.surfaceHighest, in: .rect(cornerRadius: 4))
                    }
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if let url = URL(string: runner.scopeUrlString) {
                    Button("Open in GitHub", systemImage: "safari") {
                        NSWorkspace.shared.open(url)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                Button("Diagnostic Folder (_diag)", systemImage: "folder") {
                    openDiagDirectory()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button("Close", systemImage: "xmark.circle.fill") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Tabs & Filter Bar

    private var tabBarSection: some View {
        HStack(spacing: 12) {
            Picker("Log Tab", selection: $selectedTab) {
                ForEach(RunnerConsoleLogTab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            Spacer()

            TextField("Filter log output…", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11, design: .monospaced))
                .frame(width: 190)

            Button("Refresh", systemImage: "arrow.clockwise") {
                Task { await reloadLogs() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    // MARK: - Terminal Stream

    @ViewBuilder
    private var terminalContentSection: some View {
        switch selectedTab {
        case .liveJobOutput, .serviceLog:
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 3) {
                    if filteredLogLines.isEmpty {
                        Text("No diagnostic log entries matching current filter.")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .padding(14)
                    } else {
                        ForEach(filteredLogLines) { line in
                            logLineRow(line)
                        }
                    }
                }
                .padding(14)
            }
            .background(OctoTheme.surfaceLow)

        case .environmentVariables:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    envRow("RUNNER_NAME", runner.name)
                    envRow("RUNNER_SCOPE_URL", runner.scopeUrlString)
                    envRow("RUNNER_WORKSPACE", runner.workDirectoryPath)
                    envRow("RUNNER_ROOT", runner.rootDirectoryPath ?? runner.workDirectoryPath)
                    envRow("RUNNER_LABELS", runner.labels.joined(separator: ","))
                    envRow("RUNNER_VERSION", runner.runnerVersion ?? "latest")
                    envRow("RUNNER_IMPORTED_LOCAL", runner.isImportedLocal ? "true (in-place)" : "false (managed)")
                }
                .padding(18)
            }
            .background(OctoTheme.surfaceLow)

        case .diagnostics:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Runner Diagnostic Summary")
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                    envRow("GitHub Agent ID", runner.githubRunnerId.map { String($0) } ?? "Unregistered")
                    envRow("Listener PID", runner.pid.map { String($0) } ?? "Not running")
                    envRow("Current Status", runner.status.rawValue.uppercased())
                    envRow("Last Heartbeat", runner.lastHeartbeat.formatted(date: .abbreviated, time: .standard))
                    envRow("Diagnostic Logs Loaded", "\(logLines.count) lines")
                }
                .padding(18)
            }
            .background(OctoTheme.surfaceLow)
        }
    }

    private func logLineRow(_ line: RunnerLogLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(line.timestampText)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)

            Text(line.level.rawValue)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(color(for: line.level))
                .frame(width: 38, alignment: .leading)

            Text(line.message)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)

            Spacer(minLength: 0)
        }
    }

    private func envRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(OctoTheme.accentBlue)
                .frame(width: 200, alignment: .leading)
            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 10)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 6))
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 12) {
            Toggle("Auto-scroll", isOn: $autoScroll)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))

            Text("\(filteredLogLines.count) lines")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Copy All Logs", systemImage: "doc.on.doc") {
                let combined = filteredLogLines
                    .map { "[\($0.timestampText) \($0.level.rawValue)] \($0.message)" }
                    .joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(combined, forType: .string)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Clear View", systemImage: "trash") {
                logLines.removeAll()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)

            Button("Done") {
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .controlSize(.small)
        }
    }

    private var filteredLogLines: [RunnerLogLine] {
        guard !filterText.isEmpty else { return logLines }
        return logLines.filter {
            $0.message.localizedStandardContains(filterText)
                || $0.level.rawValue.localizedStandardContains(filterText)
        }
    }

    private func color(for level: RunnerLogLevel) -> Color {
        switch level {
        case .info:
            OctoTheme.accentBlue
        case .warning:
            OctoTheme.warningOrange
        case .error:
            OctoTheme.errorRed
        case .success:
            OctoTheme.onlineGreen
        }
    }

    private func reloadLogs() async {
        isLoading = true
        defer { isLoading = false }
        let rootURL = URL(fileURLWithPath: runner.rootDirectoryPath ?? runner.workDirectoryPath)
        logLines = await logStreamer.readRecentLogLines(forRunnerRoot: rootURL, maxLines: 200)
    }

    private func openDiagDirectory() {
        let rootURL = URL(fileURLWithPath: runner.rootDirectoryPath ?? runner.workDirectoryPath)
        let diagURL = rootURL.appending(path: "_diag")
        if FileManager.default.fileExists(atPath: diagURL.path()) {
            NSWorkspace.shared.open(diagURL)
        } else {
            NSWorkspace.shared.open(rootURL)
        }
    }
}
