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
    @Environment(AppPreferencesStore.self) private var preferences: AppPreferencesStore?
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
    @State private var showMigrationOnOpen = false
    @State private var activeConsoleRunner: RunnerEntity?

    private let telemetryActor = HostTelemetryActor()
    private let updaterActor = AppUpdaterActor()
    private let syncActor = GitHubRunnerSyncActor()
    private let migrationProvisioner = RunnerProvisionerActor()
    private let jobResults: LocalJobResults
    private let supervisor: RunnerSupervisorActor
    private let launchAgents: RunnerLaunchAgentInspector?

    public init(
        section: SidebarSection = .allRunners,
        historyRateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget(),
        accountSession: AccountSessionController = AccountSessionController(),
        jobResults: LocalJobResults = LocalJobResults(),
        supervisor: RunnerSupervisorActor = RunnerSupervisorActor(),
        launchAgents: RunnerLaunchAgentInspector? = nil
    ) {
        self.jobResults = jobResults
        self.supervisor = supervisor
        self.launchAgents = launchAgents
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

                Button(AppLocalization.string("Sync Runners", locale: locale), systemImage: "arrow.triangle.2.circlepath.circle") {
                    Task { await syncLocalAndRemoteRunners(manual: true) }
                }
                .disabled(isSyncingRunners)

                Button(AppLocalization.string("Import Folder…", locale: locale), systemImage: "folder.badge.plus", action: importRunnerFolderViaOpenPanel)

                Button(AppLocalization.string("New Runner", locale: locale), systemImage: "plus") {
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
            AddRunnerWizardSheet(viewModel: AddRunnerWizardViewModel(supervisor: supervisor))
        }
        .sheet(item: $activeConfigRunner) { runner in
            RunnerConfigDetailSheet(runner: runner, supervisor: supervisor, launchConfiguration: runnerLaunchConfiguration,
                launchAgents: launchAgents, showMigrationOnOpen: showMigrationOnOpen)
        }
        .sheet(item: $activeConsoleRunner) { runner in
            RunnerConsoleLogSheet(runner: runner, supervisor: supervisor)
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

    private var runnerLaunchConfiguration: RunnerLaunchConfiguration {
        guard let preferences else { return RunnerLaunchConfiguration() }
        return RunnerLaunchConfiguration(runtimePolicy: preferences.runtimePolicy, inheritHostPath: preferences.inheritHostPath)
    }

    // MARK: - Left Sidebar + Bottom-Left Account Card & Version Footer

    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(selection: $selectedSection) {
                Section(AppLocalization.string("RUNNER STATUS", locale: locale)) {
                    ForEach(SidebarSection.allCases) { section in
                        HStack {
                            if section == .queueWorkpools {
                                Label { Text("Jobs & Workflow Runs", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else if section == .launchdSettings {
                                Label { Text("App Settings", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else if section == .hostTelemetry {
                                Label { Text("Host Telemetry", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else {
                                Label(AppLocalization.string(String.LocalizationValue(stringLiteral: section == .allRunners ? "All runners" : section.title), locale: locale), systemImage: section.systemImage)
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
                            Text(AppLocalization.string("Sign in with GitHub", locale: locale))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(AppLocalization.string("Connect OAuth or PAT", locale: locale))
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
            SettingsWindowView(accountSession: accountSession, launchAgents: launchAgents)
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
                            Button(AppLocalization.string("Dismiss", locale: locale), systemImage: "xmark") {
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
        .searchable(text: $searchText, prompt: AppLocalization.string("Search runners, labels...", locale: locale))
    }

    private func updateAvailableBanner(_ update: AppUpdateInfo) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 22))
                .foregroundStyle(OctoTheme.accentBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string("Update Available: OctoRunner v\(update.latestVersion)", locale: locale))
                    .font(.system(size: 13, weight: .bold))
                Text(AppLocalization.string("You are running v\(update.currentVersion). Click 'Install & Relaunch' to update automatically.", locale: locale))
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
                        Text(AppLocalization.string("Updating…", locale: locale))
                    } else {
                        Image(systemName: "bolt.fill")
                        Text(AppLocalization.string("Install & Relaunch", locale: locale))
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
                title: AppLocalization.string("Running Instances", locale: locale),
                value: AppLocalization.string("\(activeRunnerCount) of \(runners.count) active", locale: locale),
                subtitle: activeRunnerCount > 0 ? AppLocalization.string("Supervised by Process Actor", locale: locale) : AppLocalization.string("Engine on standby", locale: locale),
                accent: activeRunnerCount > 0 ? OctoTheme.onlineGreen : .secondary
            )
            kpiCard(
                title: AppLocalization.string("Host CPU Architecture", locale: locale),
                value: hostDisplay.cpuBrand,
                subtitle: AppLocalization.string("\(hostDisplay.coreCount) logical cores", locale: locale),
                accent: OctoTheme.accentBlue
            )
            kpiCard(
                title: AppLocalization.string("Unified Memory", locale: locale),
                value: AppLocalization.string("\(hostDisplay.memoryCapacity) GiB RAM", locale: locale),
                subtitle: AppLocalization.string("\(hostDisplay.memoryUsed) GiB used", locale: locale),
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
                Text(AppLocalization.string("Registered Runner Pool", locale: locale))
                    .font(.system(size: 15, weight: .semibold))
                Spacer()
                Text(AppLocalization.string("Instances: \(filteredRunners.count)", locale: locale))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if filteredRunners.isEmpty {
                let emptyState = RunnerPoolEmptyState(registeredCount: runners.count, section: selectedSection ?? .allRunners, search: searchText)
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
                            Button(AppLocalization.string("Sync Local & GitHub Runners", locale: locale), systemImage: "arrow.triangle.2.circlepath") {
                                Task { await syncLocalAndRemoteRunners(manual: true) }
                            }
                            .buttonStyle(.borderedProminent)

                            Button(AppLocalization.string("Import Runner Folder…", locale: locale), systemImage: "folder.badge.plus", action: importRunnerFolderViaOpenPanel)
                                .buttonStyle(.bordered)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 200)
                }
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
            openSettings: {
                showMigrationOnOpen = false
                activeConfigRunner = runner
            },
            migrate: {
                showMigrationOnOpen = true
                activeConfigRunner = runner
            },
            remove: {
                let id = runner.id
                let isDirect = runner.executionMode == .direct
                Task { await deleteRunner(id: id, isDirect: isDirect) }
            })
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

            Text(AppLocalization.string("\(hostDisplay.cpuBrand) • \(hostDisplay.memoryCapacity) GiB Unified RAM", locale: locale))
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

            Text(AppLocalization.string("Scopes: \(account.scopes.isEmpty ? AppLocalization.string("Not reported by token; permissions checked when used", locale: locale) : account.scopes.joined(separator: ", "))", locale: locale))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            Button {
                isShowingAccountPopover = false
                Task { await syncLocalAndRemoteRunners(manual: true) }
            } label: {
                Label(AppLocalization.string("Sync Local & GitHub Runners", locale: locale), systemImage: "arrow.triangle.2.circlepath.circle")
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
                Label(AppLocalization.string("Check for Updates (v\(AppUpdaterActor.currentBundleVersion))", locale: locale), systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isShowingAccountPopover = false
                isShowingAuthSheet = true
            } label: {
                Label(AppLocalization.string("Switch / Re-authenticate Account…", locale: locale), systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) {
                isShowingAccountPopover = false
                signOut(account)
            } label: {
                Label(AppLocalization.string("Sign Out @\(account.login)", locale: locale), systemImage: "rectangle.portrait.and.arrow.right")
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
        into modelContext: ModelContext,
        excludingPaths: Set<String> = []
    ) -> Int {
        guard var existingRunners = try? modelContext.fetch(FetchDescriptor<RunnerEntity>()) else { return 0 }
        var importedOrUpdated = 0

        for item in discoveredList {
            let path = LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: item.rootDirectory)
            guard !excludingPaths.contains(path) else { continue }
            let isPreviousInstallation = existingRunners.contains { runner in
                guard let original = runner.migratedSourcePath, runner.migratedSourceRemoteID == item.config.agentId else {
                    return false
                }
                return LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(filePath: original)) == path
                    && URL(string: runner.scopeUrlString)?.path.lowercased() == item.config.gitHubUrl.path.lowercased()
            }
            guard !isPreviousInstallation else { continue }
            let pathMatch = existingRunners.first { runner in
                guard let root = runner.rootDirectoryPath else { return false }
                return LocalRunnerDiscoveryActor.normalizedDirectoryPath(for: URL(filePath: root)) == path
            }
            func sameScope(_ runner: RunnerEntity) -> Bool {
                let recorded = URL(string: runner.scopeUrlString)
                let discovered = item.config.gitHubUrl
                return recorded?.scheme?.lowercased() == discovered.scheme?.lowercased()
                    && recorded?.host?.lowercased() == discovered.host?.lowercased()
                    && recorded?.port == discovered.port
                    && recorded?.path.lowercased() == discovered.path.lowercased()
            }
            if let pathMatch {
                guard sameScope(pathMatch),
                      pathMatch.githubRunnerId == nil || pathMatch.githubRunnerId == item.config.agentId else { continue }
            }
            let legacyMatch = existingRunners.first { runner in
                guard runner.executionMode != .direct, runner.executionMode != .launchAgent else { return false }
                return runner.githubRunnerId == item.config.agentId && sameScope(runner)
            }
            if let existing = pathMatch ?? legacyMatch {
                existing.githubRunnerId = item.config.agentId
                existing.name = item.config.agentName
                existing.scopeType = item.config.inferredScopeType
                existing.scopeUrlString = item.config.gitHubUrl.absoluteString
                existing.workDirectoryPath = item.workDirectory.path(percentEncoded: false)
                existing.rootDirectoryPath = item.rootDirectory.path(percentEncoded: false)
                existing.runnerVersion = item.runnerVersion
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
                existingRunners.append(entity)

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
        let protectedPaths: Set<String>
        do {
            protectedPaths = try await migrationProvisioner.migrationProtectedPaths()
        } catch {
            guard !Task.isCancelled else { return }
            if manual {
                updateStatusMessage = AppLocalization.string("Runner sync paused because OctoRunner could not read the migration journal.", locale: locale)
            }
            return
        }
        guard !Task.isCancelled else { return }
        let count = Self.upsertDiscoveredRunners(discovered, into: modelContext, excludingPaths: protectedPaths)
        if manual {
            updateStatusMessage = count > 0
                ? AppLocalization.string("Synced \(count) local runner(s) with GitHub.", locale: locale)
                : AppLocalization.string("No local .runner instances found in standard paths.", locale: locale)
        }
    }

    private func importRunnerFolderViaOpenPanel() {
        let panel = NSOpenPanel()
        panel.title = AppLocalization.string("Select Existing GitHub Actions Runner Folder", locale: locale)
        panel.message = AppLocalization.string("Choose a folder containing a configured GitHub Actions runner (.runner).", locale: locale)
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
            return AppLocalization.string("Runner status: \(faultedRunnerCount) with errors", locale: locale)
        }
        if activeRunnerCount > 0 {
            return AppLocalization.string("Runner status: \(activeRunnerCount) active", locale: locale)
        }
        return AppLocalization.string("Runner Engine: Standby (0 active runners)", locale: locale)
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

    private func deleteRunner(id: UUID, isDirect: Bool) async {
        if isDirect {
            guard await supervisor.reserveRemoval(runnerID: id) else {
                updateStatusMessage = AppLocalization.string("Stop this runner before removing it.", locale: locale)
                return
            }
        }
        var removed = false
        do {
            try Task.checkCancellation()
            let descriptor = FetchDescriptor<RunnerEntity>(predicate: #Predicate { $0.id == id })
            if let runner = try modelContext.fetch(descriptor).first,
               (runner.executionMode == .direct) == isDirect {
                try modelContext.transaction {
                    let name = runner.name
                    let oldLabels = runner.labels.joined(separator: ",")
                    modelContext.delete(runner)
                    modelContext.insert(AuditLogEntity(category: .runnerLifecycle, severity: .warning,
                        title: "Runner Removed from Pool", summary: "Removed runner \(name) (\(id.uuidString)) from local pool",
                        actorAccountLogin: accounts.first?.login, targetRunnerName: name, previousValue: oldLabels))
                }
                removed = true
            }
        } catch is CancellationError {
            // A cancelled view must release its reservation without touching SwiftData.
        } catch {
            if !Task.isCancelled {
                updateStatusMessage = AppLocalization.string("The runner could not be removed.", locale: locale)
            }
        }
        if isDirect { await supervisor.finishRemoval(runnerID: id, removed: removed) }
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
                updateStatusMessage = AppLocalization.string("OctoRunner v\(info.currentVersion) is up to date.", locale: locale)
            }
        } catch {
            if manual {
                updateStatusMessage = AppLocalization.string("Update check failed: \(error.localizedDescription)", locale: locale)
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
            updateStatusMessage = AppLocalization.string("Auto-update failed (\(error.localizedDescription)) — opening release page.", locale: locale)
            NSWorkspace.shared.open(update.releasePageURL)
        }
    }
}

#Preview("MainShellView — Populated Dashboard") {
    MainShellView()
        .frame(width: 1120, height: 740)
        .preferredColorScheme(.dark)
}
