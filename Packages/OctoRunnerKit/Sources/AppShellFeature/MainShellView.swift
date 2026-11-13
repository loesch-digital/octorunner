import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import RunnerEngine
import SwiftData
import SwiftUI
import SyncKit
import TelemetryKit

public struct MainShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]

    @State private var historyRateBudget: WorkflowHistoryRateBudget
    @State private var accountSession: AccountSessionController
    @State private var accountTask: Task<Void, Never>?
    @State private var selectedSection: SidebarSection?
    @State private var searchText: String = ""
    @State private var hostSnapshot: HostTelemetrySnapshot?
    @State private var isShowingAuditLog = false
    @State private var isShowingAuthSheet: Bool = false
    @State private var isShowingAddRunnerSheet: Bool = false
    @State private var isShowingAccountPopover: Bool = false
    @State private var isSyncingRunners: Bool = false
    @State private var updateInfo: AppUpdateInfo?
    @State private var isCheckingForUpdates: Bool = false
    @State private var isInstallingUpdate: Bool = false
    @State private var updateStatusMessage: String?

    @State private var activeConfigRunner: RunnerEntity?
    @State private var activeConsoleRunner: RunnerEntity?

    private let telemetryActor = HostTelemetryActor()
    private let updaterActor = AppUpdaterActor()
    private let syncActor = GitHubRunnerSyncActor()
    private let provisioner = RunnerProvisionerActor()
    private let jobResults: LocalJobResults

    public init(section: SidebarSection = .allRunners, historyRateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget(), accountSession: AccountSessionController = AccountSessionController(), jobResults: LocalJobResults = LocalJobResults()) {
        self.jobResults = jobResults
        _historyRateBudget = State(initialValue: historyRateBudget)
        _accountSession = State(initialValue: accountSession)
        _selectedSection = State(initialValue: section)
    }

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 285)
        } detail: {
            detailContent
        }
        .navigationTitle("OctoRunner")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { isShowingAuditLog = true } label: {
                    Label { Text("Audit Log", bundle: .module) } icon: { Image(systemName: "clock.arrow.circlepath") }
                }
                .accessibilityLabel(Text("Audit Log", bundle: .module))
                .accessibilityHint(Text("Review and export local app and runner events.", bundle: .module))

                SettingsLink {
                    Label { Text("App Settings", bundle: .module) } icon: { Image(systemName: "gearshape") }
                }
                .accessibilityLabel(Text("App Settings", bundle: .module))
                .accessibilityHint(Text("Opens OctoRunner’s application settings", bundle: .module))

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
        .sheet(isPresented: $isShowingAuditLog) { AuditLogView() }
        .sheet(isPresented: $isShowingAuthSheet) {
            OAuthDeviceFlowSheet()
        }
        .onDisappear { accountTask?.cancel() }
        .sheet(isPresented: $isShowingAddRunnerSheet) {
            AddRunnerWizardSheet()
        }
        .sheet(item: $activeConfigRunner) { runner in
            RunnerConfigDetailSheet(runner: runner)
        }
        .sheet(item: $activeConsoleRunner) { runner in
            RunnerConsoleLogSheet(runner: runner)
        }
        .task {
            let initialKey = accounts.first(where: { $0.isActive })?.keychainAccountKey
            let hasConnectedAccount = !accounts.isEmpty
            guard !Task.isCancelled else { return }
            if !hasConnectedAccount {
                isShowingAuthSheet = true
            }
            await syncLocalAndRemoteRunners(manual: false, explicitKey: initialKey)
            guard !Task.isCancelled else { return }
            await checkForAppUpdates(manual: false)
        }
        .task {
            while !Task.isCancelled {
                let snapshot = await telemetryActor.currentSnapshot()
                guard !Task.isCancelled else { return }
                hostSnapshot = snapshot
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
    }

    // MARK: - Left Sidebar + Bottom-Left Account Card & Version Footer

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section("RUNNER STATUS") {
                    ForEach(SidebarSection.allCases) { section in
                        HStack {
                            if section == .queueWorkpools {
                                Label { Text("Jobs & Workflow Runs", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else if section == .launchdSettings {
                                Label { Text("App Settings", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else if section == .hostTelemetry {
                                Label { Text("Host Telemetry", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else {
                                Label(section.title, systemImage: section.systemImage)
                            }
                            Spacer()
                            if section != .queueWorkpools && section != .launchdSettings && section != .hostTelemetry {
                              Text("\(count(for: section))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                        .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            sidebarBottomAccountCard

            Divider()

            sidebarVersionFooter
        }
    }

    private var sidebarBottomAccountCard: some View {
        Group {
            if let activeAccount = accounts.first(where: { $0.isActive }) {
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

    private var sidebarVersionFooter: some View {
        HStack {
            Text("OctoRunner v\(AppUpdaterActor.currentBundleVersion)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Circle()
                .fill(engineIndicatorColor)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(OctoTheme.surfaceLow)
    }

    // MARK: - Dashboard and Status Footer

    @ViewBuilder private var detailContent: some View {
        if selectedSection == .queueWorkpools {
            WorkflowJobHistoryView(rateBudget: historyRateBudget)
        } else if selectedSection == .launchdSettings {
            SettingsWindowView(accountSession: accountSession)
        } else if selectedSection == .hostTelemetry {
            HostTelemetryDashboardView(accountID: accounts.first(where: { $0.isActive })?.githubUserId, rateBudget: historyRateBudget)
        } else {
            runnerDashboardContent
        }
    }

    private var runnerDashboardContent: some View {
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
        .searchable(text: $searchText, prompt: "Search runners, labels...")
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

    private var hostDisplay: HostTelemetryDisplay {
        HostTelemetryDisplay(snapshot: hostSnapshot, locale: locale)
    }

    private var kpiHeaderRow: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
            kpiCard(
                title: "Running Instances",
                value: "\(activeRunnerCount) of \(runners.count) active",
                subtitle: activeRunnerCount > 0 ? "Supervised by Process Actor" : "Engine on standby",
                accent: activeRunnerCount > 0 ? OctoTheme.onlineGreen : .secondary
            )
            kpiCard(
                title: "Host CPU Architecture",
                value: hostDisplay.cpuBrand,
                subtitle: "\(hostDisplay.coreCount) logical cores",
                accent: OctoTheme.accentBlue
            )
            kpiCard(
                title: "Unified Memory",
                value: "\(hostDisplay.memoryCapacity) GiB RAM",
                subtitle: "\(hostDisplay.memoryUsed) GiB used",
                accent: OctoTheme.accentBlue
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

    // MARK: - Registered Runner Pool Card

    private var runnerListCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !jobResults.unreviewedFailures.isEmpty { JobFailureNotice(results: jobResults) }
            HStack {
                Text("Registered Runner Pool")
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text("\(filteredRunners.count) instance(s)")
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
                .frame(maxWidth: .infinity, minHeight: 200)
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
        DashboardRunnerRow(runner: runner, lastJob: jobResults.latestByRunner[runner.id],
            openLog: { activeConsoleRunner = runner },
            openSettings: { activeConfigRunner = runner },
            migrate: { Task { await migrateImportedRunnerInline(runner) } },
            remove: { deleteRunner(runner) })
    }

    private func migrateImportedRunnerInline(_ runner: RunnerEntity) async {
        guard !Task.isCancelled else { return }
        let runnerID = runner.id
        let runnerName = runner.name
        let sourcePath = runner.rootDirectoryPath ?? runner.workDirectoryPath
        let actorLogin = accounts.first(where: { $0.isActive })?.login
        do {
            let managedRoot = try await provisioner.migrateImportedRunnerDirectory(
                runnerName: runnerName,
                sourceRootDirectory: URL(fileURLWithPath: sourcePath),
                registerLaunchAgent: true
            )
            try Task.checkCancellation()
            guard let migratedName = try RunnerMigrationCompletion.apply(
                runnerID: runnerID, expectedSourcePath: sourcePath, managedRoot: managedRoot,
                context: modelContext, actorLogin: actorLogin
            ) else {
                updateStatusMessage = "Migration finished on disk, but the runner changed or was removed. Review the managed folder before retrying."
                return
            }
            updateStatusMessage = "Migrated '\(migratedName)' into OctoRunner managed pool with Autostart enabled."
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            updateStatusMessage = "Migration failed: \(error.localizedDescription)"
        }
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

            Text("\(hostDisplay.cpuBrand) • \(hostDisplay.memoryCapacity) GiB Unified RAM")
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

            Text("Scopes: \(account.scopes.isEmpty ? "Not reported by token; permissions checked when used" : account.scopes.joined(separator: ", "))")
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
                Label { Text("App Settings", bundle: .module) } icon: { Image(systemName: "gearshape") }
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
            .disabled(accountSession.isBusy)
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
                existing.workDirectoryPath = item.workDirectory.path(percentEncoded: false)
                existing.rootDirectoryPath = item.rootDirectory.path(percentEncoded: false)
                existing.runnerVersion = item.runnerVersion
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
                    rootDirectoryPath: item.rootDirectory.path(percentEncoded: false),
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

    private func syncLocalAndRemoteRunners(
        manual: Bool,
        extraDirs: [URL] = [],
        explicitKey: String? = nil
    ) async {
        let key = explicitKey ?? accounts.first(where: { $0.isActive })?.keychainAccountKey
        isSyncingRunners = true
        defer { isSyncingRunners = false }

        let discovered = await syncActor.discoverAndReconcileRunners(
            accountKey: key,
            additionalDirectories: extraDirs
        )
        guard !Task.isCancelled else { return }
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
            case .allRunners, .queueWorkpools, .launchdSettings, .hostTelemetry:
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
        case .allRunners, .queueWorkpools, .launchdSettings, .hostTelemetry:
            return runners.count
        case .activeDaemons:
            return runners.count(where: { $0.status == .idle || $0.status == .busy })
        case .failedFaulted:
            return runners.count(where: { $0.status == .faulted })
        }
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
        let id = account.id
        guard !accountSession.isBusy else { return }
        accountTask = Task {
            let success = await accountSession.disconnect(accountID: id, in: modelContext)
            guard !Task.isCancelled else { return }
            if success {
                isShowingAuthSheet = true
            } else if let error = accountSession.error {
                updateStatusMessage = error.localizedMessage(locale: locale)
            }
        }
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
        guard !Task.isCancelled else { return }
        isInstallingUpdate = true
        try? AppAuditEvent.updateStarted.record(in: modelContext)
        do {
            try await updaterActor.downloadAndInstallUpdate(from: zipURL)
            guard !Task.isCancelled else { return }
            try? AppAuditEvent.updateInstalled.record(in: modelContext)
            NSApplication.shared.terminate(nil)
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            try? AppAuditEvent.updateFailed.record(in: modelContext)
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
