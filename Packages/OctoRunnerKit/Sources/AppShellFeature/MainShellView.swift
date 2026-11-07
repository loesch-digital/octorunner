import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import SwiftData
import SwiftUI
import SyncKit
import TelemetryKit

public struct MainShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]

    @State private var selectedSection: SidebarSection? = .allRunners
    @State private var searchText: String = ""
    @State private var hostSnapshot: HostTelemetrySnapshot?
    @State private var isShowingAuthSheet: Bool = false
    @State private var isShowingAddRunnerSheet: Bool = false
    @State private var isShowingAccountPopover: Bool = false
    @State private var isSyncingRunners: Bool = false
    @State private var updateInfo: AppUpdateInfo?
    @State private var isCheckingForUpdates: Bool = false
    @State private var isInstallingUpdate: Bool = false
    @State private var updateStatusMessage: String?

    private let telemetryActor = HostTelemetryActor()
    private let oauthActor = GitHubOAuthActor()
    private let updaterActor = AppUpdaterActor()
    private let syncActor = GitHubRunnerSyncActor()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 215, ideal: 240, max: 280)
        } detail: {
            detailContent
        }
        .navigationTitle("OctoRunner")
        .searchable(text: $searchText, prompt: "Search runners, labels...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Sync Runners", systemImage: "arrow.triangle.2.circlepath.circle") {
                    Task { await syncLocalAndRemoteRunners(manual: true) }
                }
                .disabled(isSyncingRunners)

                Button("Import Folder…", systemImage: "folder.badge.plus", action: importRunnerFolderViaOpenPanel)

                Button("New Runner", systemImage: "plus") {
                    isShowingAddRunnerSheet = true
                }
                .buttonStyle(.borderedProminent)
                .tint(OctoTheme.accentBlue)
            }
        }
        .sheet(isPresented: $isShowingAuthSheet) {
            OAuthDeviceFlowSheet()
        }
        .sheet(isPresented: $isShowingAddRunnerSheet) {
            AddRunnerWizardSheet()
        }
        .task {
            hostSnapshot = await telemetryActor.currentSnapshot()
            if accounts.isEmpty {
                isShowingAuthSheet = true
            }
            await syncLocalAndRemoteRunners(manual: false)
            await checkForAppUpdates(manual: false)
        }
    }

    // MARK: - Left Sidebar + Bottom-Left Account & Settings Card (macOS App Store Style)

    private var sidebarContent: some View {
        VStack(spacing: 0) {
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

            Divider()

            sidebarBottomAccountCard
        }
    }

    private var sidebarBottomAccountCard: some View {
        Group {
            if let activeAccount = accounts.first {
                Button {
                    isShowingAccountPopover.toggle()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(OctoTheme.accentBlue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(activeAccount.displayName ?? activeAccount.login)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("@\(activeAccount.login)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(OctoTheme.accentBlue)
                                .lineLimit(1)
                        }

                        Spacer()

                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingAccountPopover, arrowEdge: .trailing) {
                    accountPopoverContent(activeAccount)
                }
            } else {
                Button {
                    isShowingAuthSheet = true
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 24))
                            .foregroundStyle(OctoTheme.accentBlue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sign in with GitHub")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Connect OAuth or PAT")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
        .background(OctoTheme.surfaceLow)
    }

    // MARK: - Detail Content + Fixed Bottom Footer

    private var detailContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let update = updateInfo, update.isUpdateAvailable {
                        updateAvailableBanner(update)
                    } else if let updateStatusMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundStyle(OctoTheme.onlineGreen)
                            Text(updateStatusMessage)
                                .font(.system(size: 12, weight: .medium))
                            Spacer()
                            Button("Dismiss", systemImage: "xmark") {
                                self.updateStatusMessage = nil
                            }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                        }
                        .padding(10)
                        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
                    }

                    kpiHeaderRow
                    runnerListCard
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            statusFooterBar
        }
        .background(OctoTheme.surfaceLowest)
    }

    private func updateAvailableBanner(_ update: AppUpdateInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 22))
                .foregroundStyle(OctoTheme.accentBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Update Available: OctoRunner v\(update.latestVersion)")
                    .font(.system(size: 13, weight: .bold))
                Text("You are running v\(update.currentVersion). Click 'Install & Relaunch' to update automatically.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await installAvailableUpdate(update) }
            } label: {
                HStack(spacing: 6) {
                    if isInstallingUpdate {
                        ProgressView().controlSize(.small)
                        Text("Updating…")
                    } else {
                        Image(systemName: "bolt.fill")
                        Text("Install & Relaunch")
                    }
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .disabled(isInstallingUpdate)
        }
        .padding(14)
        .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.accentBlue.opacity(0.6), lineWidth: 1)
        }
    }

    private var kpiHeaderRow: some View {
        HStack(spacing: 12) {
            kpiCard(
                title: "Running Instances",
                value: "\(activeRunnerCount) of \(runners.count) active",
                subtitle: activeRunnerCount > 0 ? "Supervised by Process Actor" : "Engine on standby",
                accent: activeRunnerCount > 0 ? OctoTheme.onlineGreen : .secondary
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
                Text("v\(AppUpdaterActor.currentBundleVersion)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if filteredRunners.isEmpty {
                ContentUnavailableView {
                    Label("No Runners Registered Yet", systemImage: "server.rack")
                } description: {
                    Text("Click 'Sync Runners' to auto-import local runners or 'New Runner' to register a new instance.")
                } actions: {
                    HStack(spacing: 10) {
                        Button("Sync Local & GitHub Runners", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await syncLocalAndRemoteRunners(manual: true) }
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Import Runner Folder…", systemImage: "folder.badge.plus", action: importRunnerFolderViaOpenPanel)
                            .buttonStyle(.bordered)
                    }
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
                    if runner.isImportedLocal {
                        Text("IMPORTED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(OctoTheme.accentBlue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(OctoTheme.surfaceHighest, in: .rect(cornerRadius: 4))
                    }
                    if let version = runner.runnerVersion {
                        Text("v\(version)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    if let pid = runner.pid {
                        Text("PID \(pid)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
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

    // MARK: - Bottom Status Bar

    private var statusFooterBar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(engineIndicatorColor)
                    .frame(width: 7, height: 7)
                Text(engineStatusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(hostSnapshot?.cpuSummary ?? "Apple Silicon") • \(String(format: "%.0f", hostSnapshot?.physicalMemoryGB ?? 32)) GB Unified RAM")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(OctoTheme.surface)
    }

    private func accountPopoverContent(_ account: GitHubAccountEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.checkmark")
                    .font(.system(size: 28))
                    .foregroundStyle(OctoTheme.accentBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName ?? account.login)
                        .font(.system(size: 13, weight: .bold))
                    Text("@\(account.login)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(OctoTheme.accentBlue)
                }
                Spacer()
            }

            Text("Scopes: \(account.scopes.isEmpty ? "repo, workflow, admin:org" : account.scopes.joined(separator: ", "))")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            Button {
                isShowingAccountPopover = false
                Task { await syncLocalAndRemoteRunners(manual: true) }
            } label: {
                Label("Sync Local & GitHub Runners", systemImage: "arrow.triangle.2.circlepath.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isShowingAccountPopover = false
                selectedSection = .launchdSettings
            } label: {
                Label("Settings & LaunchAgents", systemImage: "gearshape.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isShowingAccountPopover = false
                Task { await checkForAppUpdates(manual: true) }
            } label: {
                Label("Check for Updates (v\(AppUpdaterActor.currentBundleVersion))", systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isShowingAccountPopover = false
                isShowingAuthSheet = true
            } label: {
                Label("Switch / Re-authenticate Account…", systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) {
                isShowingAccountPopover = false
                signOut(account)
            } label: {
                Label("Sign Out @\(account.login)", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(OctoTheme.errorRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .frame(width: 265)
    }

    // MARK: - SyncKit Integration

    @MainActor
    @discardableResult
    public static func upsertDiscoveredRunners(
        _ discoveredList: [DiscoveredLocalRunner],
        into modelContext: ModelContext
    ) -> Int {
        let existingRunners = (try? modelContext.fetch(FetchDescriptor<RunnerEntity>())) ?? []
        var importedOrUpdated = 0

        for item in discoveredList {
            if let existing = existingRunners.first(where: {
                $0.githubRunnerId == item.config.agentId || $0.name == item.config.agentName
            }) {
                existing.githubRunnerId = item.config.agentId
                existing.name = item.config.agentName
                existing.scopeType = item.config.inferredScopeType
                existing.scopeUrlString = item.config.gitHubUrl.absoluteString
                existing.workDirectoryPath = item.workDirectory.path()
                existing.rootDirectoryPath = item.rootDirectory.path()
                existing.runnerVersion = item.runnerVersion
                existing.isImportedLocal = true
                existing.labels = item.labels
                existing.pid = item.listenerPID
                existing.status = item.localStatus
                existing.lastHeartbeat = .now
            } else {
                let entity = RunnerEntity(
                    name: item.config.agentName,
                    scopeType: item.config.inferredScopeType,
                    scopeUrl: item.config.gitHubUrl,
                    status: item.localStatus,
                    labels: item.labels,
                    workDirectory: item.workDirectory,
                    rootDirectoryPath: item.rootDirectory.path(),
                    runnerVersion: item.runnerVersion,
                    isImportedLocal: true,
                    pid: item.listenerPID
                )
                entity.githubRunnerId = item.config.agentId
                modelContext.insert(entity)

                AuditLogRecorder.record(
                    in: modelContext,
                    category: .runnerLifecycle,
                    severity: .info,
                    title: "Local Runner Auto-Imported",
                    summary: "Imported \(item.config.agentName) (agentId \(item.config.agentId), \(item.config.gitHubUrl.absoluteString))",
                    targetRunnerName: item.config.agentName,
                    newValue: item.labels.joined(separator: ",")
                )
            }
            importedOrUpdated += 1
        }

        try? modelContext.save()
        return importedOrUpdated
    }

    private func syncLocalAndRemoteRunners(manual: Bool, extraDirs: [URL] = []) async {
        isSyncingRunners = true
        defer { isSyncingRunners = false }

        let discovered = await syncActor.discoverAndReconcileRunners(
            accountLogin: accounts.first?.login,
            additionalDirectories: extraDirs
        )
        let count = Self.upsertDiscoveredRunners(discovered, into: modelContext)
        if manual {
            updateStatusMessage = count > 0
                ? "Synced \(count) local runner(s) with GitHub."
                : "No local .runner instances found in standard paths."
        }
    }

    private func importRunnerFolderViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = "Select Existing GitHub Actions Runner Folder"
        panel.message = "Choose a folder containing a configured GitHub Actions runner (.runner)."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            Task {
                await syncLocalAndRemoteRunners(manual: true, extraDirs: [url])
            }
        }
    }

    private var activeRunnerCount: Int {
        runners.count(where: { $0.status == .idle || $0.status == .busy })
    }

    private var faultedRunnerCount: Int {
        runners.count(where: { $0.status == .faulted })
    }

    private var engineIndicatorColor: Color {
        if faultedRunnerCount > 0 {
            return OctoTheme.errorRed
        }
        if activeRunnerCount > 0 {
            return OctoTheme.onlineGreen
        }
        return .secondary
    }

    private var engineStatusText: String {
        if faultedRunnerCount > 0 {
            return "Runner Engine: \(faultedRunnerCount) faulted"
        }
        if activeRunnerCount > 0 {
            return "Runner Engine: Supervising \(activeRunnerCount) active runner(s)"
        }
        return "Runner Engine: Standby (0 active runners)"
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
        let name = runner.name
        let oldLabels = runner.labels.joined(separator: ",")
        modelContext.delete(runner)
        AuditLogRecorder.record(
            in: modelContext,
            category: .runnerLifecycle,
            severity: .warning,
            title: "Runner Removed from Pool",
            summary: "Removed runner \(name) from local pool",
            actorAccountLogin: accounts.first?.login,
            targetRunnerName: name,
            previousValue: oldLabels
        )
        try? modelContext.save()
    }

    private func signOut(_ account: GitHubAccountEntity) {
        let login = account.login
        modelContext.delete(account)
        AuditLogRecorder.record(
            in: modelContext,
            category: .authentication,
            severity: .warning,
            title: "GitHub Account Signed Out",
            summary: "Signed out @\(login) and removed token from Keychain",
            actorAccountLogin: login
        )
        try? modelContext.save()
        Task {
            try? await oauthActor.signOut(login: login)
        }
        isShowingAuthSheet = true
    }

    private func checkForAppUpdates(manual: Bool) async {
        isCheckingForUpdates = true
        defer { isCheckingForUpdates = false }
        do {
            let info = try await updaterActor.checkForUpdates()
            updateInfo = info
            if manual && !info.isUpdateAvailable {
                updateStatusMessage = "OctoRunner v\(info.currentVersion) is up to date."
            }
        } catch {
            if manual {
                updateStatusMessage = "Update check failed: \(error.localizedDescription)"
            }
        }
    }

    private func installAvailableUpdate(_ update: AppUpdateInfo) async {
        guard let zipURL = update.zipDownloadURL else {
            NSWorkspace.shared.open(update.releasePageURL)
            return
        }
        isInstallingUpdate = true
        do {
            try await updaterActor.downloadAndInstallUpdate(from: zipURL)
            NSApplication.shared.terminate(nil)
        } catch {
            isInstallingUpdate = false
            updateStatusMessage = "Auto-update failed (\(error.localizedDescription)) — opening release page."
            NSWorkspace.shared.open(update.releasePageURL)
        }
    }
}

#Preview("MainShellView — Populated Dashboard") {
    MainShellView()
        .frame(width: 1120, height: 740)
        .preferredColorScheme(.dark)
}
