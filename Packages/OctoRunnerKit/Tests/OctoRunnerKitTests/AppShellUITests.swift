import AppKit
import AppShellFeature
import CoreModels
import DesignSystem
import Foundation
import GitHubAPI
import SwiftData
import SwiftUI
import SyncKit
import Testing

@Suite("AppShell UI, Layout & Preview Rendering Tests", .serialized)
struct AppShellUITests {
    @Test("OAuthDeviceFlowViewModel copies userCode to NSPasteboard and resets cleanly on cancel")
    @MainActor
    func oauthDeviceFlowClipboardCopyAndCancelState() {
        let viewModel = OAuthDeviceFlowViewModel()
        viewModel.copyUserCode("ABCD-9876")
        #expect(viewModel.copiedToClipboard == true)
        #expect(NSPasteboard.general.string(forType: .string) == "ABCD-9876")

        viewModel.cancelFlow()
        #expect(viewModel.state == .initial)
        #expect(viewModel.errorMessage == nil)
    }

    @Test("MainShellView Preview renders populated Dashboard & Account pill cleanly in NSHostingView")
    @MainActor
    func mainShellViewPreviewRendersInHostingView() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RunnerEntity.self,
            JobRunEntity.self,
            GitHubAccountEntity.self,
            configurations: config
        )
        let account = GitHubAccountEntity(
            githubUserId: 1001,
            login: "loesch-digital",
            displayName: "Frank",
            scopes: ["repo", "workflow", "admin:org"],
            keychainAccountKey: "loesch-digital"
        )
        let runner = RunnerEntity(
            name: "mac-studio-m4-runner-1",
            scopeType: .repository,
            scopeUrl: URL(string: "https://github.com/loesch-digital/octorunner")!,
            status: .idle,
            labels: ["self-hosted", "macos", "arm64"],
            workDirectory: URL(fileURLWithPath: "/tmp/octorunner-preview")
        )
        container.mainContext.insert(account)
        container.mainContext.insert(runner)
        try container.mainContext.save()

        let rootView = MainShellView()
            .modelContainer(container)
            .frame(width: 1120, height: 740)

        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = NSRect(x: 0, y: 0, width: 1120, height: 740)
        hostingView.layoutSubtreeIfNeeded()

        #expect(hostingView.bounds.width == 1120)
        #expect(hostingView.bounds.height == 740)
        #expect(!hostingView.subviews.isEmpty)

        let bitmap = hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        #expect(bitmap != nil)
        #expect(bitmap?.pixelsWide ?? 0 >= 1120)
        #expect(bitmap?.pixelsHigh ?? 0 >= 740)
    }

    @Test("OAuthDeviceFlowSheet Previews render all 3 states (Initial, Polling, Authenticated) cleanly")
    @MainActor
    func oauthSheetStatesRenderInHostingView() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RunnerEntity.self,
            JobRunEntity.self,
            GitHubAccountEntity.self,
            configurations: config
        )

        // State 1: Initial
        let vmInitial = OAuthDeviceFlowViewModel()
        let initialHost = NSHostingView(
            rootView: OAuthDeviceFlowSheet(viewModel: vmInitial).modelContainer(container)
        )
        initialHost.frame = NSRect(x: 0, y: 0, width: 580, height: 500)
        initialHost.layoutSubtreeIfNeeded()
        #expect(initialHost.bounds.size == CGSize(width: 580, height: 500))

        // State 2: Polling with large copyable userCode
        let vmPolling = OAuthDeviceFlowViewModel()
        vmPolling.state = .polling(
            GitHubDeviceCodeResponse(
                deviceCode: "dev-123",
                userCode: "WDX8-8222",
                verificationUri: URL(string: "https://github.com/login/device")!,
                expiresIn: 900,
                interval: 5
            )
        )
        vmPolling.copiedToClipboard = true
        let pollingHost = NSHostingView(
            rootView: OAuthDeviceFlowSheet(viewModel: vmPolling).modelContainer(container)
        )
        pollingHost.frame = NSRect(x: 0, y: 0, width: 580, height: 500)
        pollingHost.layoutSubtreeIfNeeded()
        #expect(pollingHost.bounds.size == CGSize(width: 580, height: 500))

        // State 3: Authenticated
        let vmAuth = OAuthDeviceFlowViewModel()
        vmAuth.state = .authenticated(
            AuthenticatedGitHubSession(
                user: GitHubUserProfileDTO(id: 42, login: "loesch-digital", name: "Frank", avatarUrl: nil),
                scopes: ["repo", "workflow", "admin:org"],
                authMethod: "oauth_device"
            )
        )
        let authHost = NSHostingView(
            rootView: OAuthDeviceFlowSheet(viewModel: vmAuth).modelContainer(container)
        )
        authHost.frame = NSRect(x: 0, y: 0, width: 580, height: 500)
        authHost.layoutSubtreeIfNeeded()
        #expect(authHost.bounds.size == CGSize(width: 580, height: 500))
    }

    @Test("DesignSystem RunnerStatusBadge renders all status variants")
    @MainActor
    func runnerStatusBadgeRendering() {
        for status in RunnerStatus.allCases {
            let host = NSHostingView(rootView: RunnerStatusBadge(status: status))
            host.frame = NSRect(x: 0, y: 0, width: 100, height: 28)
            host.layoutSubtreeIfNeeded()
            #expect(host.bounds.width == 100)
        }
    }

    @Test("MainShellView.upsertDiscoveredRunners imports local runner and updates existing entry idempotently")
    @MainActor
    func upsertDiscoveredRunnersIdempotency() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RunnerEntity.self,
            JobRunEntity.self,
            GitHubAccountEntity.self,
            configurations: config
        )
        let context = container.mainContext

        let discovered = DiscoveredLocalRunner(
            rootDirectory: URL(fileURLWithPath: "/Users/frank/Documents/apps/actions-runner"),
            config: LocalDotRunnerConfig(
                agentId: 21,
                agentName: "macbook-pro-frank",
                gitHubUrl: URL(string: "https://github.com/loesch-digital/itemflux-ios-app")!,
                workFolder: "_work"
            ),
            workDirectory: URL(fileURLWithPath: "/Users/frank/Documents/apps/actions-runner/_work"),
            runnerVersion: "2.338.2",
            listenerPID: 87558,
            isWorkerActive: false,
            labels: ["self-hosted", "macOS", "ARM64"]
        )

        // First sync imports the runner
        let importedCount = MainShellView.upsertDiscoveredRunners([discovered], into: context)
        #expect(importedCount == 1)

        var allRunners = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(allRunners.count == 1)
        #expect(allRunners.first?.name == "macbook-pro-frank")
        #expect(allRunners.first?.githubRunnerId == 21)
        #expect(allRunners.first?.pid == 87558)
        #expect(allRunners.first?.status == .idle)

        // Second sync updates in-place (no duplicate created)
        var busyDiscovered = discovered
        busyDiscovered.localStatus = .busy
        let secondCount = MainShellView.upsertDiscoveredRunners([busyDiscovered], into: context)
        #expect(secondCount == 1)

        allRunners = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(allRunners.count == 1)
        #expect(allRunners.first?.status == .busy)
    }

    @Test("AddRunnerWizardViewModel generates instance names, manages labels, multi-repo selection, and renders Step 3 & Step 4 Sheets")
    @MainActor
    func addRunnerWizardViewModelAndSheetRendering() throws {
        let vm = AddRunnerWizardViewModel()
        #expect(!vm.baseNamePrefix.contains("."))
        vm.baseNamePrefix = "mac-runner"
        vm.instanceCount = 3
        #expect(vm.previewInstanceNames == ["mac-runner-1", "mac-runner-2", "mac-runner-3"])

        vm.selectedScope = .personalMultiRepo
        vm.toggleRepositorySelection("loesch-digital/octorunner")
        vm.toggleRepositorySelection("loesch-digital/itemflux-ios-app")
        #expect(vm.selectedRepositoryFullNames.count == 2)
        #expect(vm.resolvedTargetSummaries.count == 2)

        vm.customLabelInput = "fastlane"
        vm.addCustomLabel()
        #expect(vm.selectedLabels.contains("fastlane"))
        #expect(vm.customLabelInput.isEmpty)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: RunnerEntity.self,
            JobRunEntity.self,
            GitHubAccountEntity.self,
            AuditLogEntity.self,
            configurations: config
        )
        let sampleRunner = RunnerEntity(
            name: "macbook-pro-frank",
            scopeType: .repository,
            scopeUrl: URL(string: "https://github.com/loesch-digital/itemflux-ios-app")!,
            status: .idle,
            labels: ["self-hosted", "macOS", "ARM64"],
            workDirectory: URL(fileURLWithPath: "/Users/frank/Documents/apps/actions-runner/_work"),
            rootDirectoryPath: "/Users/frank/Documents/apps/actions-runner",
            runnerVersion: "2.338.2",
            isImportedLocal: true,
            pid: 87558
        )
        container.mainContext.insert(sampleRunner)
        try container.mainContext.save()

        let host = NSHostingView(
            rootView: AddRunnerWizardSheet(viewModel: vm).modelContainer(container)
        )
        host.frame = NSRect(x: 0, y: 0, width: 640, height: 620)
        host.layoutSubtreeIfNeeded()
        #expect(host.bounds.size == CGSize(width: 640, height: 620))

        // Step 4 Dialog 4: RunnerConfigDetailSheet
        let configSheetHost = NSHostingView(
            rootView: RunnerConfigDetailSheet(runner: sampleRunner).modelContainer(container)
        )
        configSheetHost.frame = NSRect(x: 0, y: 0, width: 660, height: 580)
        configSheetHost.layoutSubtreeIfNeeded()
        #expect(configSheetHost.bounds.size == CGSize(width: 660, height: 580))

        // Step 4 Dialog 5: RunnerConsoleLogSheet
        let consoleSheetHost = NSHostingView(
            rootView: RunnerConsoleLogSheet(runner: sampleRunner).modelContainer(container)
        )
        consoleSheetHost.frame = NSRect(x: 0, y: 0, width: 820, height: 600)
        consoleSheetHost.layoutSubtreeIfNeeded()
        #expect(consoleSheetHost.bounds.size == CGSize(width: 820, height: 600))

        // Step 4 Dialog 6: MenuBarStatusView
        let menuBarHost = NSHostingView(
            rootView: MenuBarStatusView().modelContainer(container)
        )
        menuBarHost.frame = NSRect(x: 0, y: 0, width: 350, height: 460)
        menuBarHost.layoutSubtreeIfNeeded()
        #expect(menuBarHost.bounds.size == CGSize(width: 350, height: 460))
    }
}
