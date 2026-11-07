import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import SwiftData
import SwiftUI
import TelemetryKit

public struct MainShellView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]

    @State private var selectedSection: SidebarSection? = .allRunners
    @State private var searchText: String = ""
    @State private var hostSnapshot: HostTelemetrySnapshot?
    @State private var isShowingAuthSheet: Bool = false
    @State private var updateInfo: AppUpdateInfo?
    @State private var isCheckingForUpdates: Bool = false
    @State private var isInstallingUpdate: Bool = false
    @State private var updateStatusMessage: String?

    private let telemetryActor = HostTelemetryActor()
    private let oauthActor = GitHubOAuthActor()
    private let updaterActor = AppUpdaterActor()

    public init() {}

    public var body: some View {
        NavigationSplitView {
            sidebarContent
                .navigationSplitViewColumnWidth(min: 220, ideal: 245, max: 290)
                .safeAreaInset(edge: .bottom) {
                    sidebarAccountProfileCard
                }
        } detail: {
            detailContent
        }
        .navigationTitle("OctoRunner")
        .searchable(text: $searchText, prompt: "Search runners, labels...")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Check for Updates", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await checkForAppUpdates(manual: true) }
                }
                .disabled(isCheckingForUpdates || isInstallingUpdate)

                Button("Seed Demo Runner", systemImage: "sparkles", action: seedDemoRunnerIfEmpty)
                Button("New Runner", systemImage: "plus", action: seedDemoRunnerIfEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(OctoTheme.accentBlue)
            }
        }
        .sheet(isPresented: $isShowingAuthSheet) {
            OAuthDeviceFlowSheet()
        }
        .safeAreaInset(edge: .bottom) {
            statusFooterBar
        }
        .task {
            hostSnapshot = await telemetryActor.currentSnapshot()
            if accounts.isEmpty {
                isShowingAuthSheet = true
            }
            await checkForAppUpdates(manual: false)
        }
    }

    // MARK: - Sidebar + App Store Style Bottom Account Card

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

    private var sidebarAccountProfileCard: some View {
        VStack(spacing: 0) {
            Divider()
            accountMenuTrigger(compact: false)
                .padding(10)
                .background(OctoTheme.surfaceLow)
        }
    }

    @ViewBuilder
    private func accountMenuTrigger(compact: Bool) -> some View {
        if let activeAccount = accounts.first {
            Menu {
                Section("GitHub Account") {
                    if let displayName = activeAccount.displayName, !displayName.isEmpty {
                        Text("\(displayName) (@\(activeAccount.login))")
                    } else {
                        Text("Signed in as @\(activeAccount.login)")
                    }
                    Text("Auth: \(activeAccount.authMethodRaw == "oauth_device" ? "OAuth Device Flow" : "Personal Access Token")")
                    Text("Scopes: \(activeAccount.scopes.isEmpty ? "repo, workflow, admin:org" : activeAccount.scopes.joined(separator: ", "))")
                }

                Divider()

                Section("Application & Updates") {
                    if let update = updateInfo, update.isUpdateAvailable {
                        Button("Install Update v\(update.latestVersion) & Relaunch", systemImage: "arrow.down.circle.fill") {
                            Task { await installAvailableUpdate(update) }
                        }
                    } else {
                        Button("Check for Updates… (v\(AppUpdaterActor.currentBundleVersion))", systemImage: "arrow.triangle.2.circlepath") {
                            Task { await checkForAppUpdates(manual: true) }
                        }
                    }

                    Button("Open Settings & LaunchAgents", systemImage: "gearshape.fill") {
                        selectedSection = .launchdSettings
                    }
                }

                Divider()

                Button("Switch / Re-authenticate Account…", systemImage: "person.badge.key.fill") {
                    isShowingAuthSheet = true
                }
                Button("Sign Out @\(activeAccount.login)", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    signOut(activeAccount)
                }
            } label: {
                if compact {
                    HStack(spacing: 6) {
                        accountAvatarView(urlString: activeAccount.avatarUrlString, size: 18)
                        Text(activeAccount.displayName ?? "@\(activeAccount.login)")
                            .font(.system(size: 11, weight: .semibold))
                        Text("(@\(activeAccount.login))")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        accountAvatarView(urlString: activeAccount.avatarUrlString, size: 30)
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
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .menuStyle(.borderlessButton)
        } else {
            Button {
                isShowingAuthSheet = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                        .font(.system(size: compact ? 13 : 20))
                        .foregroundStyle(OctoTheme.accentBlue)
                    Text("Sign in with GitHub…")
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                    Spacer()
                }
            }
            .buttonStyle(.borderless)
        }
    }

    @ViewBuilder
    private func accountAvatarView(urlString: String?, size: CGFloat) -> some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { image in
                image
                    .resizable()
                    .scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(OctoTheme.accentBlue)
            }
            .frame(width: size, height: size)
            .clipShape(.circle)
        } else {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: size, height: size)
                .foregroundStyle(OctoTheme.accentBlue)
        }
    }

    // MARK: - Detail Content

    private var detailContent: some View {
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
                    Text("Click 'New Runner' in the toolbar to add a runner instance.")
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

    // MARK: - Bottom Status Bar (Engine Status Left, Hardware Center, Account Menu Right)

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

            Divider()
                .frame(height: 14)

            accountMenuTrigger(compact: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(OctoTheme.surface)
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
        modelContext.delete(runner)
        try? modelContext.save()
    }

    private func signOut(_ account: GitHubAccountEntity) {
        let login = account.login
        modelContext.delete(account)
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
