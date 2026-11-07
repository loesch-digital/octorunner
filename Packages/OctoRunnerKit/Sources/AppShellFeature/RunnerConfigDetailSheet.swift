import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import RunnerEngine
import SwiftData
import SwiftUI

public struct RunnerConfigDetailSheet: View {
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

    public init(runner: RunnerEntity) {
        self.runner = runner
        _editableLabels = State(initialValue: runner.labels)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerBar

            Picker("Config Section", selection: $selectedTab) {
                Text("General & Labels").tag("general")
                Text("Working Directory").tag("workspace")
                Text("Autostart & Migration").tag("autostart")
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
                    Text("Runner Settings — \(runner.name)")
                        .font(.system(size: 16, weight: .bold))
                    RunnerStatusBadge(status: runner.status)
                    if runner.isImportedLocal {
                        Text("IMPORTED")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(OctoTheme.accentBlue)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(OctoTheme.surfaceHighest, in: .rect(cornerRadius: 4))
                    }
                }
                Text("GitHub Runner ID: \(runner.githubRunnerId.map(String.init) ?? "Local") • Scope: \(runner.scopeUrlString)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var metadataAndLabelsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Runner Metadata & Assigned Capability Labels")
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Runner Name")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(runner.name)
                        .font(.system(size: 12, design: .monospaced))
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Process / Background Status")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Text(runner.pid.map { "Active (PID \(String($0)))" } ?? "Standby / Offline")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(runner.pid != nil ? OctoTheme.onlineGreen : .secondary)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
                }
            }

            Divider()

            Text("Assigned Labels (Matched by Workflow 'runs-on:')")
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
                TextField("Add capability label (e.g. fastlane, ios-18, xcode-27)…", text: $newLabelInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    .onSubmit(addCustomLabel)

                Button("Add Label", systemImage: "plus", action: addCustomLabel)
                    .buttonStyle(.bordered)
                    .disabled(newLabelInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(14)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
    }

    private var workspaceAndFileSystemCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Workspace & APFS File System")
                .font(.system(size: 13, weight: .semibold))

            VStack(alignment: .leading, spacing: 4) {
                Text("Runner Root Directory (.runner & bin/)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(runner.rootDirectoryPath ?? runner.workDirectoryPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button("Open in Finder", systemImage: "folder", action: openRootInFinder)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                .padding(8)
                .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Job Working Directory (_work)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                HStack {
                    Text(runner.workDirectoryPath)
                        .font(.system(size: 11, design: .monospaced))
                        .lineLimit(1)
                    Spacer()
                    Button("Open _work", systemImage: "folder.badge.gearshape", action: openWorkInFinder)
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
                        Text("Migrate Imported Runner into OctoRunner Managed Pool")
                            .font(.system(size: 13, weight: .bold))
                    }

                    Text(
                        "This runner is currently located at its original folder (\(runner.rootDirectoryPath ?? "external path")). Clicking 'Migrate into OctoRunner' copies the runner configuration into OctoRunner's managed Application Support directory, sets up automatic background start on macOS login, and switches management to OctoRunner."
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                    Button {
                        Task { await migrateRunnerToOctoRunner() }
                    } label: {
                        HStack(spacing: 6) {
                            if isMigrating {
                                ProgressView().controlSize(.small)
                                Text("Migrating Runner…")
                            } else {
                                Image(systemName: "bolt.horizontal.circle.fill")
                                Text("Migrate into OctoRunner & Enable Autostart")
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
            }

            Toggle(isOn: $registerBackgroundService) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Automatic Background Start on macOS Login")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Service ID: \(runner.serviceLabel)")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .padding(14)
            .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
        }
    }

    private var footerBar: some View {
        HStack {
            Button("Reset Labels", action: resetLabels)
                .buttonStyle(.borderless)

            Spacer()

            Button("Cancel") {
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
                    Text("Save & Sync Labels")
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

        let oldRoot = runner.rootDirectoryPath ?? URL(fileURLWithPath: runner.workDirectoryPath).deletingLastPathComponent().path()
        let sourceURL = URL(fileURLWithPath: oldRoot, isDirectory: true)

        do {
            let migratedRoot = try await provisionerActor.migrateImportedRunnerDirectory(
                runnerName: runner.name,
                sourceRootDirectory: sourceURL,
                registerLaunchAgent: registerBackgroundService
            )
            runner.rootDirectoryPath = migratedRoot.path()
            runner.workDirectoryPath = migratedRoot.appending(path: "_work").path()
            runner.isImportedLocal = false

            AuditLogRecorder.record(
                in: modelContext,
                category: .configuration,
                severity: .info,
                title: "Runner Migrated into OctoRunner",
                summary: "Migrated \(runner.name) from \(oldRoot) to \(migratedRoot.path())",
                actorAccountLogin: accounts.first?.login,
                targetRunnerName: runner.name,
                previousValue: oldRoot,
                newValue: migratedRoot.path()
            )
            try? modelContext.save()
            statusBannerMessage = "Successfully migrated '\(runner.name)' into OctoRunner!"
        } catch {
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

        if let login = accounts.first?.login,
           let runnerId = runner.githubRunnerId,
           let scopeURL = URL(string: runner.scopeUrlString),
           let token = try? await provisioningClient.readToken(for: login) {
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
