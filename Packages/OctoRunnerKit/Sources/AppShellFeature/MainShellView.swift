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
    @Environment(\.scenePhase) private var scenePhase
    @Environment(RunnerRemoteSyncMonitor.self) private var remoteSync: RunnerRemoteSyncMonitor?
    @Environment(AppPreferencesStore.self) private var preferences: AppPreferencesStore?
    @Environment(\.usesDashboardSampleData) private var usesDashboardSampleData
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]

    @State private var historyRateBudget: WorkflowHistoryRateBudget
    @State private var accountSession: AccountSessionController
    @State private var accountTask: Task<Void, Never>?
    @State private var selectedSection: SidebarSection?
    @State private var observedHistoryRepository = ""
    @State private var workflowJump: WorkflowHistoryEntry?
    @State private var showsRunningWorkflows = false
    @State private var searchText: String = ""
    @State private var hostSnapshot: HostTelemetrySnapshot?
    @State private var isShowingAuditLog = false
    @State private var isShowingAuthSheet: Bool = false
    @State private var isShowingAddRunnerSheet: Bool = false
    @State private var isSyncingRunners: Bool = false
    @State private var updateInfo: AppUpdateInfo?
    @State private var isCheckingForUpdates: Bool = false
    @State private var isInstallingUpdate: Bool = false
    @State private var updateStatusMessage: String?
    @State private var isShowingUpdateFailure = false

    @State private var activeConfigRunner: RunnerEntity?
    @State private var showMigrationOnOpen = false
    @State private var activeConsoleRunner: RunnerEntity?

    private let telemetryActor = HostTelemetryActor()
    private let updaterActor = AppUpdaterActor()
    private let discoveryActor = LocalRunnerDiscoveryActor()
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
            DashboardSidebar(
                selectedSection: $selectedSection, usesDashboardSampleData: usesDashboardSampleData,
                registeredRunnerCount: runners.count, activeRunnerCount: activeRunnerCount, faultedRunnerCount: faultedRunnerCount,
                jobResults: jobResults, historyObservationMaxAge: historyObservationMaxAge, historyRepositories: historyRepositories,
                engineIndicatorColor: engineIndicatorColor, account: accounts.first(where: { $0.isActive }),
                accountIsBusy: accountSession.isBusy, showAuthentication: { isShowingAuthSheet = true },
                syncRunners: { Task { await syncLocalRunners(manual: true) } },
                checkForUpdates: { Task { await checkForAppUpdates(manual: true) } }, signOut: signOut
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 285)
        } detail: {
            detailContent
        }
        .navigationTitle("OctoRunner")
        .onChange(of: selectedSection) {
            if selectedSection != .queueWorkpools {
                observedHistoryRepository = ""
                workflowJump = nil
                showsRunningWorkflows = false
            }
        }
        .task(id: sidebarHistoryRequest) { await refreshSidebarHistory(sidebarHistoryRequest) }
        .toolbar { toolbarActions }
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
        .alert(AppLocalization.string(AppUpdatePresentation.title(.installationFailed), locale: locale),
               isPresented: $isShowingUpdateFailure, presenting: updateInfo) { update in
            Button(AppLocalization.string("Open on GitHub", locale: locale)) {
                NSWorkspace.shared.open(update.releasePageURL)
            }
            Button(AppLocalization.string("Cancel", locale: locale), role: .cancel) {}
        } message: { _ in
            Text(AppLocalization.string(AppUpdatePresentation.message(.installationFailed), locale: locale))
        }
        .task {
            guard !usesDashboardSampleData else { return }
            let hasConnectedAccount = !accounts.isEmpty
            guard !Task.isCancelled else { return }
            if !hasConnectedAccount {
                isShowingAuthSheet = true
            }
            await syncLocalRunners(manual: false)
            guard !Task.isCancelled else { return }
            await checkForAppUpdates(manual: false)
        }
        .task {
            guard !usesDashboardSampleData else { return }
            while !Task.isCancelled {
                let snapshot = await telemetryActor.currentSnapshot()
                guard !Task.isCancelled else { return }
                hostSnapshot = snapshot
                do { try await Task.sleep(for: .seconds(2)) }
                catch { return }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarActions: some ToolbarContent {
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
                Task { await syncLocalRunners(manual: true) }
            }
            .disabled(isSyncingRunners)

            Button(AppLocalization.string("Import Folder…", locale: locale), systemImage: "folder.badge.plus", action: importRunnerFolderViaOpenPanel)
                .disabled(isSyncingRunners)

            Button(AppLocalization.string("New Runner", locale: locale), systemImage: "plus") {
                isShowingAddRunnerSheet = true
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
        }
    }

    private var runnerLaunchConfiguration: RunnerLaunchConfiguration {
        guard let preferences else { return RunnerLaunchConfiguration() }
        return RunnerLaunchConfiguration(runtimePolicy: preferences.runtimePolicy, inheritHostPath: preferences.inheritHostPath)
    }

    private var historyAccount: GitHubAccountEntity? {
        let active = accounts.filter(\.isActive)
        guard active.count == 1, let account = active.first, account.githubUserId > 0,
              !account.keychainAccountKey.isEmpty else { return nil }
        return account
    }

    private var historyRepositories: Set<String> {
        guard let account = historyAccount, let preferences else { return [] }
        return WorkflowHistorySelection.configuredRepositories(for: runners, accountID: account.githubUserId,
            preferences: preferences.historyPreferences)
    }

    private var historyObservationMaxAge: TimeInterval {
        (preferences?.historyPreferences ?? WorkflowHistoryPreferences()).observationMaxAge
    }

    private var sidebarHistoryRequest: WorkflowHistoryRequest? {
        guard !usesDashboardSampleData, scenePhase == .active, let preferences, let account = historyAccount else { return nil }
        if selectedSection == .queueWorkpools && observedHistoryRepository.isEmpty { return nil }
        // With job alerts enabled, the existing app-lifetime monitor refreshes these sources.
        if preferences.notificationPolicy.enabled && preferences.notificationPolicy.jobFailure,
           runners.contains(where: { ($0.githubRunnerId ?? 0) > 0 }) { return nil }

        let history = preferences.historyPreferences.validated()
        let sources = historyRepositories.sorted().filter { $0 != observedHistoryRepository }.map {
            WorkflowHistorySelection(accountID: account.githubUserId, keychainAccountKey: account.keychainAccountKey, repository: $0)
        }
        guard !sources.isEmpty else { return nil }
        return WorkflowHistoryRequest(account: sources.first, sources: sources, selectedRepository: "",
            isActive: true, refreshInterval: history.refreshIntervalSeconds, ticket: account.id)
    }

    private func refreshSidebarHistory(_ request: WorkflowHistoryRequest?) async {
        guard !Task.isCancelled, let request else { return }
        let model = WorkflowHistoryViewModel(rateBudget: historyRateBudget, acceptResponse: { sidebarHistoryRequest == request })
        while !Task.isCancelled, sidebarHistoryRequest == request {
            await model.refreshRepositories(request.sources, in: modelContext)
            guard !Task.isCancelled, model.error != .authenticationRequired else { return }
            let delay = max(Double(request.refreshInterval), model.retryNotBefore?.timeIntervalSinceNow ?? 0)
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
        }
    }

    // MARK: - Dashboard and Status Footer

    @ViewBuilder private var detailContent: some View {
        if selectedSection == .queueWorkpools {
            WorkflowJobHistoryView(rateBudget: historyRateBudget, initialRun: workflowJump, showsRunning: showsRunningWorkflows) {
                observedHistoryRepository = $0
            }
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
                        DashboardUpdateBanner(update: update, isInstallingUpdate: isInstallingUpdate) {
                            Task { await installAvailableUpdate(update) }
                        }
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

                    DashboardHostMetrics(runnerCount: runners.count, activeRunnerCount: activeRunnerCount, hostDisplay: hostDisplay)
                    DashboardRunnerPool(
                        runners: filteredRunners, registeredCount: runners.count, section: selectedSection ?? .allRunners,
                        searchText: searchText, jobResults: jobResults, isSyncingRunners: isSyncingRunners,
                        syncRunners: { Task { await syncLocalRunners(manual: true) } },
                        importRunner: importRunnerFolderViaOpenPanel, runnerRow: runnerRow
                    )
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            DashboardStatusBar(engineIndicatorColor: engineIndicatorColor, engineStatusText: engineStatusText, hostDisplay: hostDisplay)
        }
        .background(OctoTheme.surfaceLowest)
        .searchable(text: $searchText, prompt: AppLocalization.string("Search runners, labels...", locale: locale))
    }

    private var hostDisplay: HostTelemetryDisplay {
        HostTelemetryDisplay(snapshot: hostSnapshot, locale: locale)
    }

    private func runnerRow(_ runner: RunnerEntity, usage: RunnerResourceUsage?) -> some View {
        let observation = remoteSync?.snapshot.flatMap { snapshot in
            accounts.first(where: { $0.isActive }).flatMap {
                RunnerSyncObservation(runner: runner, account: $0, snapshot: snapshot)
            }
        }
        var row = DashboardRunnerRow(runner: runner, lastJob: jobResults.latestByRunner[runner.id], syncObservation: observation,
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
        row.resourceUsage = usage
        row.currentJobControl = DashboardRunnerJobControl(results: jobResults, runnerID: runner.id, isRunning: runner.status == .busy,
            observationMaxAge: historyObservationMaxAge) { job in
            guard runner.status == .busy else { return }
            workflowJump = job
            showsRunningWorkflows = true
            selectedSection = .queueWorkpools
        }
        return row
    }

    // MARK: - SyncKit Integration

    private func syncLocalRunners(manual: Bool) async {
        guard !Task.isCancelled, !isSyncingRunners else { return }
        isSyncingRunners = true
        await scanReservedLocalFolders(manual: manual, extraDirs: [])
        if manual, !Task.isCancelled { await remoteSync?.refresh(in: modelContext) }
    }

    private func scanReservedLocalFolders(manual: Bool, extraDirs: [URL]) async {
        defer { isSyncingRunners = false }
        guard !Task.isCancelled else { return }
        let discovered = await discoveryActor.discoverAllLocalRunners(additionalDirectories: extraDirs)
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
        let count = LocalRunnerImportStore.upsert(discovered, into: modelContext, excludingPaths: protectedPaths)
        if manual {
            updateStatusMessage = count > 0
                ? AppLocalization.string("Local runner records refreshed: \(count).", locale: locale)
                : AppLocalization.string("No local runner records were updated.", locale: locale)
        }
    }

    private func importRunnerFolderViaOpenPanel() {
        guard !isSyncingRunners else { return }
        isSyncingRunners = true
        let panel = NSOpenPanel()
        panel.title = AppLocalization.string("Select Existing GitHub Actions Runner Folder", locale: locale)
        panel.message = AppLocalization.string("Choose a folder containing a configured GitHub Actions runner (.runner).", locale: locale)
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true

        guard panel.runModal() == .OK, let url = panel.url else {
            isSyncingRunners = false
            return
        }
        Task {
            await scanReservedLocalFolders(manual: true, extraDirs: [url])
            guard !Task.isCancelled else { return }
            await remoteSync?.refresh(in: modelContext)
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
        defer { isInstallingUpdate = false }
        try? AppAuditEvent.updateStarted.record(in: modelContext)
        do {
            let staged = try await updaterActor.downloadAndStageUpdate(from: zipURL, expectedVersion: update.latestVersion)
            do {
                try Task.checkCancellation()
                try AppUpdateHandoff.schedule(staged)
            } catch {
                staged.discard()
                throw error
            }
            NSApplication.shared.terminate(nil)
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            try? AppAuditEvent.updateFailed.record(in: modelContext)
            isShowingUpdateFailure = true
        }
    }
}

extension EnvironmentValues {
    @Entry var usesDashboardSampleData = false
}
