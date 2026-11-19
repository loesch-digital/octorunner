import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import RunnerEngine
import SwiftData
import SwiftUI

public struct RunnerConfigDetailSheet: View {
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
    @State private var statusBannerMessage: String?
    @State private var errorMessage: String?

    private let provisioningClient = GitHubRunnerProvisioningClient()
    private let provisionerActor = RunnerProvisionerActor()
    private let supervisor: RunnerSupervisorActor?
    private let launchConfiguration: RunnerLaunchConfiguration
    private let launchAgents: RunnerLaunchAgentInspector?

    public init(runner: RunnerEntity, supervisor: RunnerSupervisorActor? = nil,
                launchConfiguration: RunnerLaunchConfiguration = RunnerLaunchConfiguration(),
                launchAgents: RunnerLaunchAgentInspector? = nil) {
        self.runner = runner
        self.supervisor = supervisor
        self.launchConfiguration = launchConfiguration
        self.launchAgents = launchAgents
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
                }
            }

            Divider()

            footerBar
        }
        .padding(22)
        .frame(width: 660, height: 580)
        .background(OctoTheme.surfaceLowest)
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

            HStack(spacing: 8) {
                TextField(AppLocalization.string("Add capability label (e.g. fastlane, ios-18, xcode-27)…", locale: locale), text: $newLabelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(addCustomLabel)

                Button(AppLocalization.string("Add Label", locale: locale), systemImage: "plus", action: addCustomLabel)
                    .buttonStyle(.bordered)
                    .disabled(newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
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
            if runner.isImportedLocal {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.doc.on.clipboard")
                            .foregroundStyle(OctoTheme.accentBlue)
                        Text(AppLocalization.string("Migrate Imported Runner into OctoRunner Managed Pool", locale: locale))
                            .font(.system(size: 13, weight: .bold))
                    }

                    Text(AppLocalization.string(
                        "This runner is currently located at its original folder (\(runner.rootDirectoryPath ?? AppLocalization.string("external path", locale: locale))). Migration copies its configuration into OctoRunner’s Application Support folder. You can also enable automatic startup at login.", locale: locale)
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    Toggle(isOn: $registerBackgroundService) {
                        Text("Automatic Background Start on macOS Login", bundle: .module)
                    }
                    .accessibilityHint(Text("Installs a LaunchAgent when the runner is migrated.", bundle: .module))

                    Button {
                        Task { await migrateRunnerToOctoRunner() }
                    } label: {
                        HStack(spacing: 6) {
                            if isMigrating {
                                ProgressView().controlSize(.small)
                                Text(AppLocalization.string("Migrating Runner…", locale: locale))
                            } else {
                                Image(systemName: "bolt.horizontal.circle.fill")
                                Text(AppLocalization.string("Migrate into OctoRunner", locale: locale))
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(OctoTheme.accentBlue)
                    .disabled(isMigrating)
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
                Task { await saveChangesAndSyncGitHub() }
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
            .disabled(isSaving)
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

    private func migrateRunnerToOctoRunner() async {
        isMigrating = true
        errorMessage = nil
        defer { isMigrating = false }

        let runnerID = runner.id
        let runnerName = runner.name
        let sourcePath = runner.rootDirectoryPath ?? runner.workDirectoryPath
        let sourceURL = if let root = runner.rootDirectoryPath {
            URL(filePath: root, directoryHint: .isDirectory)
        } else {
            URL(filePath: runner.workDirectoryPath).deletingLastPathComponent()
        }
        let launchAgentInstalled = registerBackgroundService
        let actorLogin = accounts.first(where: { $0.isActive })?.login

        do {
            let migratedRoot = try await provisionerActor.migrateImportedRunnerDirectory(
                runnerName: runnerName,
                sourceRootDirectory: sourceURL,
                registerLaunchAgent: launchAgentInstalled
            )
            guard let migratedName = try RunnerMigrationCompletion.apply(
                runnerID: runnerID, expectedSourcePath: sourcePath, managedRoot: migratedRoot,
                context: modelContext, actorLogin: actorLogin, launchAgentInstalled: launchAgentInstalled
            ) else {
                errorMessage = AppLocalization.string("Migration finished on disk, but the runner changed or was removed. Review the managed folder before retrying.", locale: locale)
                return
            }
            statusBannerMessage = AppLocalization.string("Successfully migrated '\(migratedName)' into OctoRunner!", locale: locale)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func saveChangesAndSyncGitHub() async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }

        let previousLabels = runner.labels.joined(separator: ",")
        let updatedLabels = editableLabels.joined(separator: ",")
        runner.labels = editableLabels

        if let key = accounts.first(where: { $0.isActive })?.keychainAccountKey, !key.isEmpty,
           let runnerId = runner.githubRunnerId,
           let scopeURL = URL(string: runner.scopeUrlString),
           let token = try? await provisioningClient.readToken(for: key) {
            _ = try? await provisioningClient.replaceRunnerLabels(
                scopeURL: scopeURL,
                runnerId: runnerId,
                labels: editableLabels,
                token: token
            )
        }

        if previousLabels != updatedLabels {
            AuditLogRecorder.record(
                in: modelContext,
                category: .configuration,
                severity: .info,
                title: "Runner Labels Updated",
                summary: "Updated labels for \(runner.name)",
                actorAccountLogin: accounts.first?.login,
                targetRunnerName: runner.name,
                previousValue: previousLabels,
                newValue: updatedLabels
            )
        }

        try? modelContext.save()
        dismiss()
    }
}
