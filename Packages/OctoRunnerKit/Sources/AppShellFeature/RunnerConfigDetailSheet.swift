import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import RunnerEngine
import SwiftData
import SwiftUI
import SyncKit

public struct RunnerConfigDetailSheet: View {
    private struct ReviewedMigration: Identifiable {
        var id: UUID { request.runnerID }
        let plan: RunnerMigrationPlan
        let request: RunnerMigrationRequest
        let originalPath: String
        let accountLogin: String
    }

    @Environment(RunnerRemoteSyncMonitor.self) private var remoteSync: RunnerRemoteSyncMonitor?
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]

    @Bindable var runner: RunnerEntity

    @State private var selectedTab: String = "general"
    @State private var editableLabels: [String] = []
    @State private var newLabelInput: String = ""
    @State private var registerBackgroundService: Bool = true
    @State private var isSaving: Bool = false
    @State private var isMigrating: Bool = false
    @State private var migrationTask: Task<Void, Never>?
    @State private var labelsTask: Task<Void, Never>?
    @State private var labelUpdate: RunnerRemoteLabelUpdate?
    @State private var reviewedLabels: RunnerRemoteLabelReview?
    @State private var reviewedMigration: ReviewedMigration?
    @State private var pendingRecovery: RunnerMigrationRecovery?
    @State private var unreadableRecovery = false
    @State private var recoveryCheckedFor: UUID?
    @State private var isShowingRecovery = false
    @State private var statusBannerMessage: String?
    @State private var errorMessage: String?

    private let syncClient = GitHubRunnerSyncActor()
    private let provisioningClient = GitHubRunnerProvisioningClient()
    private let provisionerActor = RunnerProvisionerActor()
    private let supervisor: RunnerSupervisorActor?
    private let launchConfiguration: RunnerLaunchConfiguration
    private let launchAgents: RunnerLaunchAgentInspector?

    public init(runner: RunnerEntity, supervisor: RunnerSupervisorActor? = nil,
                launchConfiguration: RunnerLaunchConfiguration = RunnerLaunchConfiguration(),
                launchAgents: RunnerLaunchAgentInspector? = nil, showMigrationOnOpen: Bool = false) {
        self.runner = runner
        self.supervisor = supervisor
        self.launchConfiguration = launchConfiguration
        self.launchAgents = launchAgents
        _selectedTab = State(initialValue: showMigrationOnOpen ? "autostart" : "general")
        _editableLabels = State(initialValue: runner.labels)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar

            Picker(AppLocalization.string("Config Section", locale: locale), selection: $selectedTab) {
                Text(AppLocalization.string("General & Labels", locale: locale)).tag("general")
                Text(AppLocalization.string("Working Directory", locale: locale)).tag("workspace")
                Text(AppLocalization.string("Autostart & Migration", locale: locale)).tag("autostart")
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if selectedTab == "general" {
                        metadataAndLabelsCard
                    } else if selectedTab == "workspace" {
                        workspaceAndFileSystemCard
                    } else {
                        autostartAndMigrationCard
                    }
                }
                .padding(.vertical, 2)
            }

            if let statusBannerMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(OctoTheme.onlineGreen)
                    Text(statusBannerMessage)
                        .font(.system(size: 12))
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 6))
            }

            if let errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(OctoTheme.errorRed)
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(OctoTheme.errorRed)
                        .textSelection(.enabled)
                }
            }

            Divider()

            footerBar
        }
        .padding(22)
        .frame(width: 660, height: 580)
        .background(OctoTheme.surfaceLowest)
        .interactiveDismissDisabled(isMigrating || isSaving)
        .onDisappear {
            migrationTask?.cancel()
            labelsTask?.cancel()
        }
        .task(id: runner.id) { await loadRecovery(for: runner.id) }
        .alert(Text("Adopt GitHub Labels?", bundle: .module), isPresented: Binding(
            get: { reviewedLabels != nil }, set: { if !$0 { reviewedLabels = nil } }
        ), presenting: reviewedLabels) { review in
            Button { adoptGitHubLabels(review) } label: { Text("Adopt Locally", bundle: .module) }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: { review in
            Text("Labels reported by @\(review.accountLogin): \(review.githubLabels.joined(separator: ", "))", bundle: .module)
        }
        .confirmationDialog(Text("Replace Custom Labels on GitHub?", bundle: .module), isPresented: Binding(
            get: { labelUpdate != nil }, set: { if !$0 { labelUpdate = nil } }
        ), titleVisibility: .visible, presenting: labelUpdate) { update in
            Button {
                labelsTask = Task { await applyVerifiedLabelUpdate(update) }
            } label: {
                Text("Apply on GitHub", bundle: .module)
            }
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: { update in
            Text("Replace \(labelSummary(update.previousCustomLabels)) with \(labelSummary(update.customLabels)) on \(update.configuration.agentName)?", bundle: .module)
        }
        .sheet(item: $reviewedMigration) { review in
            RunnerMigrationConfirmation(
                runnerName: review.plan.runnerName, account: review.accountLogin, source: review.plan.sourceDirectory,
                destination: review.plan.destination, scope: review.plan.scope, group: review.plan.group?.name,
                labels: review.request.labels, launchAgent: review.plan.launchAgent,
                onCancel: { reviewedMigration = nil },
                onConfirm: {
                    reviewedMigration = nil
                    migrationTask = Task { await confirmMigration(review) }
                }
            )
        }
        .sheet(isPresented: $isShowingRecovery) {
            RunnerMigrationRecoveryView(
                recovery: pendingRecovery, error: errorMessage, isWorking: isMigrating,
                discard: pendingRecovery?.stage == .preparing ? { runRecovery(discard: true) } : nil,
                retry: canRetryMigrationStartup ? { runRecovery(discard: false) } : nil
            )
        }
    }

    private var headerBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 20))
                .foregroundStyle(OctoTheme.accentBlue)
                .frame(width: 38, height: 38)
                .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(AppLocalization.string("Runner Settings — \(runner.name)", locale: locale))
                        .font(.system(size: 16, weight: .bold))
                    RunnerStatusBadge(status: runner.status)
                    if runner.isImportedLocal {
                        Text(AppLocalization.string("Imported", locale: locale))
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(OctoTheme.accentBlue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(OctoTheme.surfaceHighest, in: .rect(cornerRadius: 4))
                    }
                }
                Text(AppLocalization.string("GitHub Runner ID: \(runner.githubRunnerId.map(String.init) ?? AppLocalization.string("Local", locale: locale)) • Scope: \(runner.scopeUrlString)", locale: locale))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var metadataAndLabelsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Runner Metadata & Assigned Capability Labels", locale: locale))
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("Runner Name", locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(runner.name)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLocalization.string("Process / Background Status", locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(runner.pid.map { AppLocalization.string("Active (PID \(String($0)))", locale: locale) } ?? AppLocalization.string("Standby / Offline", locale: locale))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(runner.pid != nil ? OctoTheme.onlineGreen : .secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
                }
            }

            if let snapshot = remoteSync?.snapshot, let account = accounts.first(where: { $0.isActive }),
               let observation = RunnerSyncObservation(runner: runner, account: account, snapshot: snapshot) {
                RunnerSyncStatusView(observation: observation, showsDetails: true)
            }

            if let supervisor, runner.executionMode == .direct,
               let root = runner.rootDirectoryPath, root.hasPrefix("/") {
                Divider()
                RunnerProcessControls(configuration: .init(runnerID: runner.id, name: runner.name,
                    rootDirectory: URL(filePath: root), mode: .direct, launch: launchConfiguration), supervisor: supervisor)
            }

            Divider()

            Text(AppLocalization.string("Assigned Labels (Matched by Workflow 'runs-on:')", locale: locale))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)

            if let snapshot = remoteSync?.snapshot, let account = accounts.first(where: { $0.isActive }),
               let review = RunnerRemoteLabelReview(snapshot: snapshot, runner: runner, account: account) {
                Button { reviewedLabels = review } label: {
                    Label { Text("Review GitHub Labels…", bundle: .module) } icon: {
                        Image(systemName: "arrow.down.circle")
                    }
                }
                .accessibilityHint(Text("Reviews different labels before applying them to OctoRunner.", bundle: .module))
                .disabled(!canEditLabels)
            }

            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach(editableLabels, id: \.self) { label in
                        HStack(spacing: 4) {
                            Text(label)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                            if label.lowercased() != "self-hosted" {
                                Button {
                                    removeLabel(label)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 5))
                    }
                }
            }
            .scrollIndicators(.hidden)
            .disabled(!canEditLabels)

            HStack(spacing: 8) {
                TextField(AppLocalization.string("Add capability label (e.g. fastlane, ios-18, xcode-27)…", locale: locale), text: $newLabelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(addCustomLabel)

                Button(AppLocalization.string("Add Label", locale: locale), systemImage: "plus", action: addCustomLabel)
                    .buttonStyle(.bordered)
                    .disabled(newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .disabled(!canEditLabels)
        }
        .padding(14)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
    }

    private var workspaceAndFileSystemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(AppLocalization.string("Workspace & APFS File System", locale: locale))
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string("Runner Root Directory (.runner & bin/)", locale: locale))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(runner.rootDirectoryPath ?? runner.workDirectoryPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button(AppLocalization.string("Open in Finder", locale: locale), systemImage: "folder", action: openRootInFinder)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(8)
                .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(AppLocalization.string("Job Working Directory (_work)", locale: locale))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(runner.workDirectoryPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button(AppLocalization.string("Open _work", locale: locale), systemImage: "folder.badge.gearshape", action: openWorkInFinder)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(8)
                .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
            }
        }
        .padding(14)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
    }

    private var autostartAndMigrationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            if pendingRecovery != nil || unreadableRecovery {
                Button { isShowingRecovery = true } label: {
                    Label { Text("Review Migration Recovery", bundle: .module) } icon: {
                        Image(systemName: "exclamationmark.triangle")
                    }
                }
                .accessibilityHint(Text("Opens the last recorded migration stage and recovery instructions.", bundle: .module))
                .disabled(isSaving)
            }
            if runner.isImportedLocal {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.doc.on.clipboard")
                            .foregroundStyle(OctoTheme.accentBlue)
                        Text(AppLocalization.string("Migrate Imported Runner into OctoRunner Managed Pool", locale: locale))
                            .font(.system(size: 13, weight: .bold))
                    }

                    Text("Stop the existing runner and disable its previous automatic startup before reviewing the migration.", bundle: .module)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    Toggle(isOn: $registerBackgroundService) {
                        Text("Automatic Background Start on macOS Login", bundle: .module)
                    }
                    .accessibilityHint(Text("Installs a LaunchAgent when the runner is migrated.", bundle: .module))
                    .disabled(isMigrating)

                    Button {
                        migrationTask = Task { await prepareMigration() }
                    } label: {
                        HStack(spacing: 6) {
                            if isMigrating {
                                ProgressView().controlSize(.small)
                                Text(AppLocalization.string("Migrating Runner…", locale: locale))
                            } else {
                                Image(systemName: "bolt.horizontal.circle.fill")
                                Text("Review Runner Migration", bundle: .module)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OctoTheme.accentBlue)
                    .accessibilityHint(Text("Checks the selected runner folder and its GitHub registration.", bundle: .module))
                    .disabled(isMigrating || isSaving || pendingRecovery != nil || unreadableRecovery)
                }
                .padding(14)
                .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(OctoTheme.accentBlue.opacity(0.5), lineWidth: 1)
                }
            } else if let launchAgents, let target = runner.launchAgentTarget {
                RunnerLaunchAgentPanel(runnerID: runner.id, target: target, inspector: launchAgents)
                    .padding(14)
                    .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
            } else if runner.executionMode == .direct {
                Text("This runner is managed by OctoRunner while the app is open.", bundle: .module)
                    .foregroundStyle(OctoTheme.secondaryText)
            } else {
                Text("No managed LaunchAgent is assigned to this runner.", bundle: .module)
                    .foregroundStyle(OctoTheme.secondaryText)
            }
        }
    }

    private var footerBar: some View {
        HStack {
            Button(AppLocalization.string("Reset Labels", locale: locale), action: resetLabels)
                .buttonStyle(.borderless)

            Spacer()

            Button(AppLocalization.string("Cancel", locale: locale)) {
                dismiss()
            }

            Button {
                prepareLabelUpdate()
            } label: {
                HStack(spacing: 6) {
                    if isSaving {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "bolt.fill")
                    }
                    Text(AppLocalization.string("Save & Sync Labels", locale: locale))
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .accessibilityHint(Text("Reviews the custom labels before replacing them on GitHub.", bundle: .module))
            .disabled(!canEditLabels)
        }
        .disabled(isMigrating || isSaving)
    }

    private func adoptGitHubLabels(_ review: RunnerRemoteLabelReview) {
        guard canEditLabels else { return }
        do {
            guard try review.apply(snapshot: remoteSync?.snapshot, in: modelContext) else {
                errorMessage = AppLocalization.string("The runner or account changed. Refresh and review the labels again.", locale: locale)
                return
            }
            editableLabels = runner.labels
            errorMessage = nil
            statusBannerMessage = AppLocalization.string("GitHub labels applied locally.", locale: locale)
        } catch {
            errorMessage = AppLocalization.string("GitHub labels could not be saved.", locale: locale)
        }
    }

    private func addCustomLabel() {
        let trimmed = newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if !editableLabels.contains(trimmed) {
            editableLabels.append(trimmed)
        }
        newLabelInput = ""
    }

    private func removeLabel(_ label: String) {
        editableLabels.removeAll { $0 == label }
    }

    private func resetLabels() {
        editableLabels = runner.labels
    }

    private func openRootInFinder() {
        let path = runner.rootDirectoryPath ?? runner.workDirectoryPath
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
    }

    private func openWorkInFinder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: runner.workDirectoryPath)
    }

    private func prepareMigration() async {
        guard !Task.isCancelled, !isMigrating, !isSaving else { return }
        isMigrating = true
        errorMessage = nil
        defer { isMigrating = false }

        guard let sourcePath = runner.rootDirectoryPath,
              let remoteID = runner.githubRunnerId, let scope = URL(string: runner.scopeUrlString) else {
            errorMessage = migrationMessage(for: RunnerMigrationError.runnerIdentityMismatch)
            return
        }
        guard let account = accounts.first(where: { $0.isActive }) else {
            errorMessage = migrationMessage(for: RunnerMigrationError.runnerNotAccessible)
            return
        }
        let login = account.login
        let request = RunnerMigrationRequest(runnerID: runner.id, name: runner.name, remoteRunnerID: remoteID,
            sourceDirectory: URL(filePath: sourcePath, directoryHint: .isDirectory), scope: scope, labels: runner.labels,
            accountKey: account.keychainAccountKey, launchAgent: registerBackgroundService)

        do {
            let plan = try await provisionerActor.prepareMigration(request)
            try Task.checkCancellation()
            reviewedMigration = ReviewedMigration(plan: plan, request: request, originalPath: sourcePath, accountLogin: login)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = migrationMessage(for: error)
            if error as? RunnerMigrationError == .recoveryRequired {
                await loadRecovery(for: request.runnerID)
            }
        }
    }

    private func confirmMigration(_ review: ReviewedMigration) async {
        guard !Task.isCancelled, !isMigrating, !isSaving, let supervisor else { return }
        isMigrating = true
        errorMessage = nil
        defer { isMigrating = false }
        let request = review.request
        let context = modelContext

        do {
            guard accounts.first(where: { $0.isActive })?.keychainAccountKey == request.accountKey else {
                throw RunnerMigrationError.runnerNotAccessible
            }
            try await provisionerActor.confirmMigration(review.plan, launch: launchConfiguration, supervisor: supervisor,
                launchAgents: launchAgents) { registration in
                    guard try RunnerMigrationCompletion.apply(
                        runnerID: request.runnerID, expectedSourcePath: review.originalPath, managedRoot: review.plan.destination,
                        context: context, actorLogin: review.accountLogin, launchAgentInstalled: request.launchAgent,
                        oldRemoteID: request.remoteRunnerID, newRemoteID: registration.remoteID, installedVersion: registration.version
                    ) != nil else { throw RunnerMigrationError.runnerIdentityMismatch }
                }
            try Task.checkCancellation()
            statusBannerMessage = AppLocalization.string("Runner migration completed.", locale: locale)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = migrationMessage(for: error)
            if error as? RunnerMigrationError == .recoveryRequired {
                AuditLogRecorder.record(in: context, category: .configuration, severity: .warning,
                    title: "Runner Migration Needs Recovery", summary: "Check the last recorded migration stage.",
                    actorAccountLogin: review.accountLogin, targetRunnerName: request.name)
                await loadRecovery(for: request.runnerID)
                guard !Task.isCancelled else { return }
                isShowingRecovery = true
            }
        }
    }

    private func loadRecovery(for runnerID: UUID) async {
        do {
            let recovery = try await provisionerActor.migrationRecovery(for: runnerID)
            guard !Task.isCancelled else { return }
            pendingRecovery = recovery
            unreadableRecovery = false
            recoveryCheckedFor = runnerID
        } catch {
            guard !Task.isCancelled else { return }
            pendingRecovery = nil
            unreadableRecovery = true
            recoveryCheckedFor = nil
        }
    }

    private var canRetryMigrationStartup: Bool {
        guard let recovery = pendingRecovery, let remoteID = runner.githubRunnerId, recovery.newRemoteID != nil else {
            return false
        }
        if runner.isImportedLocal {
            return [.registered, .committing].contains(recovery.stage) && recovery.version != nil && recovery.launchAgent != nil
                && remoteID == recovery.oldRemoteID && RunnerMigrationCompletion.matchesPath(runner.rootDirectoryPath, recovery.source)
        }
        guard [.starting, .committing].contains(recovery.stage) else { return false }
        return remoteID == recovery.newRemoteID && RunnerMigrationCompletion.matchesPath(runner.rootDirectoryPath, recovery.destination)
    }

    private func runRecovery(discard: Bool) {
        migrationTask = Task { await recoverMigration(discard: discard) }
    }

    private func recoverMigration(discard: Bool) async {
        guard !Task.isCancelled, !isMigrating, !isSaving else { return }
        let runnerID = runner.id
        isMigrating = true
        errorMessage = nil
        defer { isMigrating = false }
        do {
            if discard {
                try await provisionerActor.discardInterruptedMigrationPreparation(for: runnerID)
            } else {
                guard canRetryMigrationStartup, let supervisor, let recovery = pendingRecovery,
                      let remoteID = recovery.newRemoteID, let background = recovery.launchAgent,
                      let scope = URL(string: runner.scopeUrlString),
                      let account = accounts.first(where: { $0.isActive }) else {
                    throw RunnerMigrationError.recoveryRequired
                }
                let context = modelContext
                let accountLogin = account.login
                let commit: (@MainActor @Sendable (RunnerMigrationRecovery, RunnerMigrationRegistration) throws -> Void)?
                if runner.isImportedLocal {
                    commit = { entry, registration in
                        guard try RunnerMigrationCompletion.apply(
                            runnerID: entry.runnerID, expectedSourcePath: entry.source.path, managedRoot: entry.destination,
                            context: context, actorLogin: accountLogin, launchAgentInstalled: background,
                            oldRemoteID: entry.oldRemoteID, newRemoteID: registration.remoteID, installedVersion: registration.version
                        ) != nil else { throw RunnerMigrationError.runnerIdentityMismatch }
                    }
                } else {
                    commit = nil
                }
                let configuration = ManagedRunnerConfiguration(runnerID: runnerID, name: runner.name,
                    rootDirectory: recovery.destination, mode: background ? .launchAgent : .direct, launch: launchConfiguration)
                try await provisionerActor.retryMigrationStartup(configuration: configuration, remoteID: remoteID,
                    scope: scope, labels: runner.labels, accountKey: account.keychainAccountKey,
                    supervisor: supervisor, launchAgents: launchAgents, commit: commit)
            }
            try Task.checkCancellation()
            await loadRecovery(for: runnerID)
            guard !Task.isCancelled else { return }
            isShowingRecovery = false
            if !discard {
                statusBannerMessage = AppLocalization.string("Runner migration completed.", locale: locale)
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = migrationMessage(for: error)
        }
    }

    private func migrationMessage(for error: any Error) -> String {
        let key: String.LocalizationValue = switch error as? RunnerMigrationError {
        case .unverifiedSource, .sourceChanged:
            "OctoRunner could not verify the runner folder. Check the original folder before trying again."
        case .runnerIdentityMismatch:
            "The imported runner does not match its GitHub registration. Refresh the runner and check its repository or organization."
        case .runnerNotAccessible:
            "The selected account cannot access this runner on GitHub. Check the account and runner permissions."
        case .runnerBusy:
            "This runner is executing a job. Wait for the job to finish before stopping the runner."
        case .listenerStillRunning:
            "The original runner is still running or GitHub has not marked it offline. Stop it and try again when it is offline."
        case .labelsChanged, .incompatibleRunnerLabels:
            "The current GitHub labels cannot be preserved. Check the runner labels and refresh the runner."
        case .groupChanged:
            "OctoRunner could not confirm the original runner group. Check the group and the selected account’s permissions."
        case .recoveryRequired:
            "The migration needs recovery. Review the last recorded stage before restarting a runner."
        case .conflictingService:
            "A background service with the destination name already exists. Check it before trying again."
        case .sourceServiceInstalled:
            "The original GitHub runner service is still installed. Stop and uninstall the old service first. Keep the runner registered on GitHub."
        case .unsupportedSourcePolicy:
            "OctoRunner cannot preserve this runner’s ephemeral or pinned-update configuration."
        case nil:
            "OctoRunner could not complete this migration step. Check the runner folder and GitHub access."
        }
        return AppLocalization.string(key, locale: locale)
    }

    private func labelSummary(_ labels: [String]) -> String {
        labels.isEmpty ? AppLocalization.string("No custom labels", locale: locale) : labels.joined(separator: ", ")
    }

    private var canEditLabels: Bool {
        recoveryCheckedFor == runner.id && pendingRecovery == nil && !unreadableRecovery && !isMigrating && !isSaving
    }

    private func prepareLabelUpdate() {
        guard canEditLabels else { return }
        guard let snapshot = remoteSync?.snapshot, let account = accounts.first(where: { $0.isActive }),
              let update = RunnerRemoteLabelUpdate(snapshot: snapshot, runner: runner, account: account,
                                                   draft: editableLabels) else {
            errorMessage = AppLocalization.string("Refresh the GitHub runner before changing its labels.", locale: locale)
            return
        }
        labelUpdate = update
    }

    private func applyVerifiedLabelUpdate(_ update: RunnerRemoteLabelUpdate) async {
        guard !Task.isCancelled, canEditLabels, let remoteSync else { return }
        isSaving = true
        errorMessage = nil
        var updateInProgress = false
        defer {
            if updateInProgress { remoteSync.endLabelUpdate() }
            isSaving = false
        }
        var submitted = false
        do {
            let token = try await provisioningClient.readToken(for: update.selection.credentialKey)
            guard try update.isCurrent(in: modelContext),
                  case .found(let remote, _) = try await syncClient.lookupRunner(for: update.configuration, token: token),
                  try update.isCurrent(in: modelContext), update.matchesReviewedRemote(remote) else {
                errorMessage = AppLocalization.string("The runner or account changed. Refresh and review the labels again.", locale: locale)
                return
            }
            guard await remoteSync.beginLabelUpdate() else { return }
            updateInProgress = true
            guard try update.isCurrent(in: modelContext) else {
                errorMessage = AppLocalization.string("The runner or account changed. Refresh and review the labels again.", locale: locale)
                return
            }
            submitted = true
            let names = try await provisioningClient.replaceRunnerLabels(scopeURL: update.configuration.gitHubUrl,
                runnerId: update.configuration.agentId, labels: update.customLabels, token: token)
            guard try update.apply(names, in: modelContext) else {
                errorMessage = AppLocalization.string("Refresh the GitHub runner to verify which labels were saved.", locale: locale)
                return
            }
            editableLabels = names
            statusBannerMessage = AppLocalization.string("GitHub confirmed the new labels.", locale: locale)
            remoteSync.endLabelUpdate()
            updateInProgress = false
            await remoteSync.refresh(in: modelContext)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = submitted
                ? AppLocalization.string("Refresh the GitHub runner to verify which labels were saved.", locale: locale)
                : AppLocalization.string("GitHub labels could not be saved.", locale: locale)
        }
    }
}
