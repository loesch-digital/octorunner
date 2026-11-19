import AppKit
import CoreModels
import DesignSystem
import RunnerEngine
import SwiftUI

public enum RunnerConsoleLogTab: String, CaseIterable, Identifiable, Sendable {
    case liveJobOutput = "Live Runner Output"
    case serviceLog = "Background Service Log"
    case environmentVariables = "Environment Variables"
    case diagnostics = "Runner Diagnostics"

    public var id: String { rawValue }

    var displaysLog: Bool { self != .environmentVariables }
}

public struct RunnerConsoleLogSheet: View {
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    public let runner: RunnerEntity

    @State private var selectedTab: RunnerConsoleLogTab = .liveJobOutput
    @State private var console = RunnerConsolePresentation()
    @State private var filterText: String = ""
    @State private var filterLevel: RunnerLogLevel?
    @State private var autoScroll: Bool = true
    @State private var isFollowing = false
    @State private var refreshID = UUID()
    @State private var isExporting = false
    @State private var exportDocument: RunnerConsoleExportDocument?
    @State private var showsExportError = false

    private let supervisor: RunnerSupervisorActor?
    private let logStreamer = RunnerLogStreamerActor()

    public init(runner: RunnerEntity, supervisor: RunnerSupervisorActor? = nil) {
        self.runner = runner
        self.supervisor = supervisor
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
        .frame(minWidth: 620, idealWidth: 820, minHeight: 460, idealHeight: 600)
        .background(OctoTheme.surfaceLowest)
        .task(id: Subscription(tab: selectedTab, refreshID: refreshID)) {
            await followLogs(tab: selectedTab)
        }
        .fileExporter(isPresented: $isExporting, document: exportDocument,
                      contentTypes: [.plainText], defaultFilename: "OctoRunner-diagnostics") { result in
            if case .failure = result { showsExportError = true }
        }
        .alert(Text("Could not export the log.", bundle: .module), isPresented: $showsExportError) {
            Button { showsExportError = false } label: { Text("Done", bundle: .module) }
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

                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(Array(Set(runner.labels)).sorted(), id: \.self) { label in
                            Text(verbatim: label)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(OctoTheme.surfaceHighest, in: .rect(cornerRadius: 4))
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            Spacer()

            HStack(spacing: 8) {
                if let url = URL(string: runner.scopeUrlString), url.scheme == "https", url.host == "github.com" {
                    Button(AppLocalization.string("Open in GitHub", locale: locale), systemImage: "safari") {
                        NSWorkspace.shared.open(url)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                Button(AppLocalization.string("Diagnostic Folder (_diag)", locale: locale), systemImage: "folder") {
                    openDiagDirectory()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)

                Button(AppLocalization.string("Close", locale: locale), systemImage: "xmark.circle.fill") {
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
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                tabPicker.pickerStyle(.segmented).fixedSize(horizontal: true, vertical: false)
                tabPicker.pickerStyle(.menu)
            }
            if selectedTab.displaysLog {
                HStack(spacing: 12) {
                    TextField(AppLocalization.string("Filter log output…", locale: locale), text: $filterText)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityHint(Text("Searches the displayed log messages.", bundle: .module))
                    Picker(selection: $filterLevel) {
                        Text("All Levels", bundle: .module).tag(nil as RunnerLogLevel?)
                        ForEach(RunnerLogLevel.allCases) { level in
                            Text(verbatim: level.rawValue).tag(Optional(level))
                        }
                    } label: { Text("Log Level", bundle: .module) }
                    .fixedSize()
                    .accessibilityHint(Text("Shows only entries with the selected severity.", bundle: .module))
                    Button(AppLocalization.string("Refresh", locale: locale), systemImage: "arrow.clockwise") {
                        refreshID = UUID()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .accessibilityHint(Text("Reconnects to the selected log source.", bundle: .module))
                }
            }
        }
    }

    private var tabPicker: some View {
        Picker(AppLocalization.string("Log Tab", locale: locale), selection: $selectedTab) {
            ForEach(RunnerConsoleLogTab.allCases) { tab in
                Text(AppLocalization.string(String.LocalizationValue(stringLiteral: tab.rawValue), locale: locale)).tag(tab)
            }
        }
        .labelsHidden()
        .accessibilityHint(Text("Chooses the log source or runner environment.", bundle: .module))
    }

    // MARK: - Terminal Stream

    @ViewBuilder
    private var terminalContentSection: some View {
        switch selectedTab {
        case .liveJobOutput, .serviceLog, .diagnostics:
            VStack(alignment: .leading, spacing: 0) {
                if console.wasClipped {
                    Text("Earlier or oversized log entries were omitted.", bundle: .module)
                        .foregroundStyle(OctoTheme.secondaryText)
                        .padding(.horizontal, 14)
                        .padding(.top, 8)
                }
                logResults
            }
            .background(OctoTheme.surfaceLow)

        case .environmentVariables:
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    envRow("RUNNER_NAME", runner.name)
                    envRow("RUNNER_SCOPE_URL", runner.scopeUrlString)
                    envRow(AppLocalization.string("Runner work directory", locale: locale), runner.workDirectoryPath)
                    envRow("RUNNER_ROOT", runner.rootDirectoryPath ?? runner.workDirectoryPath)
                    envRow("RUNNER_LABELS", runner.labels.joined(separator: ","))
                    envRow("RUNNER_VERSION", runner.runnerVersion ?? "latest")
                    envRow("RUNNER_IMPORTED_LOCAL", runner.isImportedLocal ? "true (in-place)" : "false (managed)")
                }
                .padding(18)
            }
            .background(OctoTheme.surfaceLow)
        }
    }

    private var logResults: some View {
        ScrollViewReader { scroll in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if selectedTab == .diagnostics { diagnosticSummary }
                    if filteredLogLines.isEmpty {
                        Text("No diagnostic log entries matching current filter.", bundle: .module)
                            .foregroundStyle(OctoTheme.secondaryText)
                    }
                    ForEach(filteredLogLines) { line in
                        logLineRow(line)
                    }
                    Color.clear.frame(height: 1).id("end-of-log")
                }
                .padding(14)
            }
            .background(OctoTheme.surfaceLow)
            .onChange(of: filteredLogLines.last?.id) {
                if autoScroll { scroll.scrollTo("end-of-log", anchor: .bottom) }
            }
            .onChange(of: autoScroll) {
                if autoScroll { scroll.scrollTo("end-of-log", anchor: .bottom) }
            }
        }
    }

    private var diagnosticSummary: some View {
        DisclosureGroup {
            envRow(AppLocalization.string("GitHub Agent ID", locale: locale), runner.githubRunnerId.map { String($0) } ?? AppLocalization.string("Unregistered", locale: locale))
            envRow(AppLocalization.string("Listener PID", locale: locale), runner.pid.map { String($0) } ?? AppLocalization.string("Not running", locale: locale))
            envRow(AppLocalization.string("Current Status", locale: locale), runner.status.localizedBadgeTitle(locale: locale))
            envRow(AppLocalization.string("Last Heartbeat", locale: locale), runner.lastHeartbeat.formatted(date: .abbreviated, time: .standard))
        } label: {
            Text("Runner Diagnostic Summary", bundle: .module)
        }
        .accessibilityHint(Text("Shows the runner identity and last observed status.", bundle: .module))
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
        VStack(alignment: .leading, spacing: 10) {
            if selectedTab.displaysLog {
                HStack(spacing: 12) {
                    Text(isFollowing
                         ? AppLocalization.string("Watching for new local log entries.", locale: locale)
                         : AppLocalization.string("Log source unavailable.", locale: locale))
                        .foregroundStyle(OctoTheme.secondaryText)
                    Spacer()
                    Text(AppLocalization.string("\(filteredLogLines.count) lines", locale: locale))
                        .foregroundStyle(OctoTheme.secondaryText)
                        .monospacedDigit()
                }
                .font(.callout)
            }
            HStack(spacing: 8) {
                if selectedTab.displaysLog { logControls }
                Spacer()
                Button(AppLocalization.string("Done", locale: locale)) { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .tint(OctoTheme.accentBlue)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    @ViewBuilder
    private var logControls: some View {
        Toggle(AppLocalization.string("Auto-scroll", locale: locale), isOn: $autoScroll)
            .toggleStyle(.checkbox)
            .accessibilityHint(Text("Keeps the newest visible entry in view.", bundle: .module))
        Button {
            console.togglePause()
        } label: {
            Label {
                if console.isPaused { Text("Resume Log", bundle: .module) }
                else { Text("Pause Log", bundle: .module) }
            } icon: {
                Image(systemName: console.isPaused ? "play.fill" : "pause.fill")
            }
        }
        .accessibilityHint(Text("Pauses or resumes updates to the log view.", bundle: .module))
        Button(AppLocalization.string("Clear View", locale: locale), systemImage: "trash") {
            console.clear()
        }
        .accessibilityHint(Text("Clears the displayed entries.", bundle: .module))
        Menu {
            Button {
                let text = RunnerConsoleExportDocument.formattedText(
                    from: console.exportContext, retaining: Set(filteredLogLines.map(\.id)))
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            } label: {
                Label { Text("Copy Redacted Log", bundle: .module) } icon: { Image(systemName: "doc.on.doc") }
            }
            Button {
                exportDocument = RunnerConsoleExportDocument(
                    lines: console.exportContext, retaining: Set(filteredLogLines.map(\.id)))
                isExporting = true
            } label: {
                Label { Text("Save Redacted Log…", bundle: .module) } icon: { Image(systemName: "square.and.arrow.down") }
            }
        } label: {
            Label { Text("Export Log", bundle: .module) } icon: { Image(systemName: "square.and.arrow.up") }
        }
        .disabled(filteredLogLines.isEmpty)
        .accessibilityHint(Text("Copies or saves the filtered entries with recognized credentials removed.", bundle: .module))
    }

    private var filteredLogLines: [RunnerLogLine] {
        console.lines.filter { line in
            (filterLevel == nil || line.level == filterLevel)
                && (filterText.isEmpty || line.message.localizedStandardContains(filterText)
                    || line.level.rawValue.localizedStandardContains(filterText))
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

    private struct Subscription: Hashable {
        let tab: RunnerConsoleLogTab
        let refreshID: UUID
    }

    private func followLogs(tab: RunnerConsoleLogTab) async {
        guard !Task.isCancelled else { return }
        console = RunnerConsolePresentation()
        isFollowing = tab.displaysLog
        guard tab.displaysLog else { return }
        let runnerID = runner.id
        let mode = runner.executionMode ?? (runner.launchAgentTarget == nil ? nil : .launchAgent)
        let rootURL = URL(fileURLWithPath: runner.rootDirectoryPath ?? runner.workDirectoryPath)
        let stream: AsyncStream<RunnerLogSnapshot>
        if tab == .liveJobOutput, mode == .direct, let supervisor {
            stream = await supervisor.consoleLogs(for: runnerID)
        } else {
            let serviceLog = tab == .serviceLog || (tab == .liveJobOutput && mode == .launchAgent)
            stream = await logStreamer.followFileLogs(forRunnerRoot: rootURL, source: serviceLog ? .launchAgent : .diagnostics)
        }
        for await snapshot in stream {
            guard !Task.isCancelled else { return }
            console.receive(snapshot)
        }
        if !Task.isCancelled { isFollowing = false }
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

#Preview("Runner Console — German, Compact") {
    RunnerConsoleLogSheet(runner: RunnerEntity(name: "mac-runner-2",
        scopeUrl: URL(string: "https://github.com/octocat/Hello-World")!,
        workDirectory: URL(fileURLWithPath: "/tmp/octorunner-preview/_work")))
        .frame(width: 620, height: 520)
        .environment(\.locale, Locale(identifier: "de"))
        .preferredColorScheme(.dark)
}
