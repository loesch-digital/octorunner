import AppKit
@testable import AppShellFeature
import CoreModels
import DesignSystem
import Foundation
import GitHubAPI
import SwiftData
import SwiftUI
import Testing

@Suite("AppShell UI, Layout & Preview Rendering Tests", .serialized)
struct AppShellUITests {
    @Test("Jobs route renders in the main application with the shared preferences")
    @MainActor
    func jobsRouteRenders() throws {
        let container = try Self.makePreviewContainer()
        let host = NSHostingView(rootView: MainShellView(section: .queueWorkpools)
            .environment(AppPreferencesStore()).modelContainer(container))
        host.frame = CGRect(x: 0, y: 0, width: 1120, height: 740)
        host.layoutSubtreeIfNeeded()
        #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
        host.rootView = MainShellView(section: .allRunners).environment(AppPreferencesStore()).modelContainer(container)
    }

    @Test("Quit confirmation cancels safely and only explicit confirmation terminates the app")
    @MainActor
    func quitConfirmationRequiresExplicitChoice() {
        let alert = AppQuitConfirmation.makeAlert()
        #expect(alert.buttons.count == 2)
        #expect(alert.buttons[1].keyEquivalent == "\u{1b}")
        #expect(AppQuitConfirmation.shouldTerminate(after: .alertFirstButtonReturn))
        #expect(!AppQuitConfirmation.shouldTerminate(after: .alertSecondButtonReturn))
        #expect(!AppQuitConfirmation.shouldTerminate(after: .abort))
    }

    // AppKit may retain SwiftUI render work beyond an NSHostingView's lifetime.
    // Keep its SwiftData stores alive until the test process exits (macOS 15).
    @MainActor private static var previewContainers: [ModelContainer] = []

    @MainActor
    private static func makePreviewContainer() throws -> ModelContainer {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        previewContainers.append(container)
        return container
    }

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
    func mainShellViewPreviewRendersInHostingView() async throws {
        do {
            let container = try DashboardPreview.makeContainer()
            Self.previewContainers.append(container)
            #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
            let accounts = try container.mainContext.fetch(FetchDescriptor<GitHubAccountEntity>())
            #expect(accounts.map(\.login) == ["build-example"])
            #expect(accounts.allSatisfy { $0.keychainAccountKey.isEmpty })
            let runners = try container.mainContext.fetch(FetchDescriptor<RunnerEntity>())
            #expect(Set(runners.map(\.status)) == [.idle, .busy, .offline])

            let rootView = DashboardPreview(container: container, language: .english)
                .frame(width: 1120, height: 740)
                .preferredColorScheme(.light)

            let hostingView = NSHostingView(rootView: AnyView(rootView))
            hostingView.appearance = NSAppearance(named: .aqua)
            hostingView.frame = NSRect(x: 0, y: 0, width: 1120, height: 740)
            hostingView.layoutSubtreeIfNeeded()

            #expect(hostingView.bounds.width == 1120)
            #expect(hostingView.bounds.height == 740)
            #expect(!hostingView.subviews.isEmpty)

            let bitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
            #expect(bitmap.pixelsWide >= 1120)
            #expect(bitmap.pixelsHigh >= 740)
            if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                let window = NSWindow(contentRect: hostingView.frame,
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: .aqua)
                window.contentView = hostingView
                hostingView.layoutSubtreeIfNeeded()
                let windowBitmap = try #require(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
                hostingView.cacheDisplay(in: hostingView.bounds, to: windowBitmap)
                let url = URL(filePath: path).appending(path: "dashboard-en-light.png")
                try #require(windowBitmap.representation(using: .png, properties: [:])).write(to: url)
                window.contentView = nil
            }

            // Tear down the view and container before suspended startup work resumes.
            hostingView.rootView = AnyView(EmptyView())
            hostingView.layoutSubtreeIfNeeded()
        }
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    @MainActor
    @Test("Capture the runner wizard and live console with example data",
          .enabled(if: ProcessInfo.processInfo.environment["OCTORUNNER_DOC_CAPTURE_DIR"] != nil))
    func captureRunnerScreens() async throws {
        let output = URL(filePath: try #require(ProcessInfo.processInfo.environment["OCTORUNNER_DOC_CAPTURE_DIR"]))
        let container = try Self.makePreviewContainer()
        let wizard = AddRunnerWizardViewModel()
        wizard.selectedScope = .repository
        wizard.manualTargetInput = "build-example/mobile"
        wizard.instanceCount = 2
        wizard.baseNamePrefix = "mac-studio"
        let wizardView = AddRunnerWizardSheet(viewModel: wizard)
            .environment(AppPreferencesStore()).modelContainer(container)
        try await capture(wizardView, size: CGSize(width: 820, height: 720), to: output.appending(path: "wizard.png"))

        let folder = FileManager.default.temporaryDirectory.appending(path: "OctoDocumentation-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let diagnostics = folder.appending(path: "_diag")
        try FileManager.default.createDirectory(at: diagnostics, withIntermediateDirectories: true)
        let log = """
        [INFO Runner] Connected to GitHub Actions
        [INFO Runner] Listening for Jobs
        2026-11-20 09:30:00Z: Running job: Build and Test
        [INFO Worker] Checking out build-example/mobile
        [INFO Worker] Running Swift package tests
        [INFO Worker] 128 tests passed
        2026-11-20 09:34:00Z: Job Build and Test completed with result: Succeeded
        """
        try log.write(to: diagnostics.appending(path: "Runner_Documentation.log"), atomically: true, encoding: .utf8)
        let scope = try #require(URL(string: "https://github.com/build-example/mobile"))
        let runner = RunnerEntity(name: "mac-studio-1", scopeUrl: scope, status: .idle,
            labels: ["self-hosted", "macOS", "ARM64", "ios"], workDirectory: folder)
        container.mainContext.insert(runner)
        try await capture(RunnerConsoleLogSheet(runner: runner).modelContainer(container),
            size: CGSize(width: 900, height: 600), to: output.appending(path: "console.png"))
    }

    @MainActor
    private func capture(_ view: some View, size: CGSize, to url: URL) async throws {
        let locale = Locale(identifier: "en_US")
        let root = view.environment(\.locale, locale).preferredColorScheme(.light)
            .frame(width: size.width, height: size.height)
        let host = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        defer { window.contentView = nil; window.close() }
        try await Task.sleep(for: .milliseconds(250))
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try #require(bitmap.representation(using: .png, properties: [:])).write(to: url)
    }

    @Test("OAuthDeviceFlowSheet Previews render all 3 states (Initial, Polling, Authenticated) cleanly")
    @MainActor
    func oauthSheetStatesRenderInHostingView() throws {
        let container = try Self.makePreviewContainer()

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

        let container = try Self.makePreviewContainer()
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
            rootView: AddRunnerWizardSheet(viewModel: vm)
                .environment(AppPreferencesStore())
                .modelContainer(container)
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
        for (width, language, scheme): (CGFloat, String, ColorScheme) in
            [(620, "de", .dark), (960, "en", .light)] {
            let view = RunnerConsoleLogSheet(runner: sampleRunner)
                .modelContainer(container)
                .environment(\.locale, Locale(identifier: language))
                .preferredColorScheme(scheme)
            let viewport = CGSize(width: width, height: 600)
            let consoleSheetHost = NSHostingView(
                rootView: view
            )
            consoleSheetHost.frame = NSRect(origin: .zero, size: viewport)
            consoleSheetHost.layoutSubtreeIfNeeded()
            #expect(consoleSheetHost.bounds.size == viewport)
            let measured = NSHostingController(rootView: view).sizeThatFits(in: viewport)
            #expect(measured.width <= viewport.width && measured.height <= viewport.height)
        }

        // Step 4 Dialog 6: MenuBarStatusView
        let menuServices = AppServices()
        let menuBarHost = NSHostingView(
            rootView: MenuBarStatusView().modelContainer(container)
                .environment(menuServices.preferences)
                .environment(menuServices.integration)
        )
        menuBarHost.frame = NSRect(x: 0, y: 0, width: 350, height: 460)
        menuBarHost.layoutSubtreeIfNeeded()
        #expect(menuBarHost.bounds.size == CGSize(width: 350, height: 460))
    }

    @Test("WCAG 2.2 AA/AAA contrast ratios pass in both Dark Mode and Light Mode, and DashboardWindowCoordinator prevents duplicate windows")
    @MainActor
    func wcag22ContrastAndSingleWindowCoordinator() {
        // Dark Mode contrast checks (WCAG 2.2 AA requires >= 4.5:1 for normal text, >= 7.0:1 AAA for primary text)
        let darkPrimaryRatio = OctoTheme.wcagContrastRatio(
            foregroundRGB: (0.95, 0.95, 0.97),
            backgroundRGB: OctoTheme.darkSurfaceRGB
        )
        let darkSecondaryRatio = OctoTheme.wcagContrastRatio(
            foregroundRGB: (0.72, 0.74, 0.78),
            backgroundRGB: OctoTheme.darkSurfaceRGB
        )
        #expect(darkPrimaryRatio >= 7.0)
        #expect(darkSecondaryRatio >= 4.5)

        // Light Mode contrast checks (WCAG 2.2 AA requires >= 4.5:1 for normal text, >= 7.0:1 AAA for primary text)
        let lightPrimaryRatio = OctoTheme.wcagContrastRatio(
            foregroundRGB: (0.08, 0.08, 0.10),
            backgroundRGB: OctoTheme.lightSurfaceRGB
        )
        let lightSecondaryRatio = OctoTheme.wcagContrastRatio(
            foregroundRGB: (0.28, 0.30, 0.35),
            backgroundRGB: OctoTheme.lightSurfaceRGB
        )
        #expect(lightPrimaryRatio >= 7.0)
        #expect(lightSecondaryRatio >= 4.5)

        // Single-window coordinator prevents duplicate Dashboard windows
        #expect(DashboardWindowCoordinator.shouldOpenNewWindow(visibleWindowTitles: ["OctoRunner"]) == false)
        #expect(DashboardWindowCoordinator.shouldOpenNewWindow(visibleWindowTitles: []) == true)
    }
}
