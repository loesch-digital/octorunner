import AppKit
#if DEBUG
@_spi(Testing) import AppShellFeature
#else
import AppShellFeature
#endif
import CoreModels
import GitHubAPI
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
public final class OctoRunnerAppDelegate: NSObject, NSApplicationDelegate, ObservableObject {
    static var updateStartup: (StagedAppUpdate, ModelContainer)?
    let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    let services = AppServices()
    @Published private(set) var isReadyForActions = OctoRunnerAppDelegate.updateStartup == nil
    lazy var modelContainer: ModelContainer = {
        if let updateStartup = Self.updateStartup { return updateStartup.1 }
        guard !isPreview else {
            do { return try OctoRunnerPersistence.makeInMemoryContainer() }
            catch { preconditionFailure("Could not initialize the preview store: \(error)") }
        }
        return OctoRunnerPersistence.makeSharedContainer()
    }()
    private let notificationPresenter = NotificationPresentationDelegate()
    private var isQuitRequestPending = false

    public func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isPreview else { return }
        if let (update, _) = Self.updateStartup {
            do {
                let context = modelContainer.mainContext
                try AppAuditEvent.updateInstalled.record(in: context)
                try AppUpdateHandoff.confirmStartup(update)
            } catch {
                // Missing acknowledgment makes the installer restore the previous bundle and store.
                exit(EXIT_FAILURE)
            }
            Task {
                do {
                    try await AppUpdateHandoff.completeStartup()
                    Self.updateStartup = nil
                    isReadyForActions = true
                    startServices()
                } catch {
                    exit(EXIT_FAILURE)
                }
            }
            return
        }
        startServices()
        if let notice = AppUpdateHandoff.takeStartupNotice() {
            try? AppAuditEvent.updateFailed.record(in: modelContainer.mainContext)
            let locale = services.preferences.language.locale
            Task { AppUpdatePresentation.makeAlert(notice, locale: locale).runModal() }
        }
    }

    private func startServices() {
        try? AppAuditEvent.started.record(in: modelContainer.mainContext)
        UNUserNotificationCenter.current().delegate = notificationPresenter
        services.startRecoveryMonitoring(container: modelContainer)
        Task {
            await services.backgroundMonitoring.resumeForeground()
            services.healthMonitor.start(container: modelContainer)
        }
        services.remoteSyncMonitor.start(container: modelContainer)
        services.diskMonitor.start()
        services.storageMaintenance.start(container: modelContainer)
        services.jobFailureMonitor.start(container: modelContainer)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        guard !isPreview, isReadyForActions else { return }
        services.stopRecoveryMonitoring()
        services.healthMonitor.stop()
        services.remoteSyncMonitor.stop()
        services.diskMonitor.stop()
        services.storageMaintenance.stop()
        services.jobFailureMonitor.stop()
        try? AppAuditEvent.stopped.record(in: modelContainer.mainContext)
    }

    public func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isPreview, isReadyForActions else { return .terminateNow }
        guard !isQuitRequestPending else { return .terminateLater }
        let locale = services.preferences.language.locale
        let confirmation = AppQuitConfirmation.makeAlert(
            locale: locale,
            keepsMonitoring: services.backgroundMonitoring.state == .enabled && !AppUpdateHandoff.isUpdatePending
        )
        guard AppQuitConfirmation.shouldTerminate(after: confirmation.runModal()) else {
            AppUpdateHandoff.cancelPending()
            return .terminateCancel
        }
        isQuitRequestPending = true
        Task {
            do {
                try await services.supervisor.shutdownForQuit()
                do {
                    if #available(macOS 27.0, *), services.backgroundMonitoring.state == .enabled,
                       !AppUpdateHandoff.isUpdatePending {
                        sender.setActivationPolicy(.regular)
                    }
                    try await services.backgroundMonitoring.prepareToQuit(
                        in: modelContainer.mainContext,
                        updating: AppUpdateHandoff.isUpdatePending
                    )
                    try AppUpdateHandoff.approvePending()
                } catch {
                    await services.backgroundMonitoring.resumeForeground()
                    await services.supervisor.resumeAfterAbortedQuit()
                    isQuitRequestPending = false
                    AppUpdateHandoff.cancelPending()
                    sender.reply(toApplicationShouldTerminate: false)
                    AppQuitConfirmation.makeBackgroundHandoffError(locale: locale).runModal()
                    return
                }
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                isQuitRequestPending = false
                AppUpdateHandoff.cancelPending()
                sender.reply(toApplicationShouldTerminate: false)
                AppQuitConfirmation.makeBlockedAlert(error: error, locale: locale).runModal()
            }
        }
        return .terminateLater
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    public func applicationDidUpdate(_ notification: Notification) {
        guard !isPreview, !isQuitRequestPending else { return }
        // Re-evaluate after AppKit processes window and preference changes, including
        // when the dashboard is closed. A visible Settings window also keeps its Dock icon.
        services.integration.applyDockVisibility(hasVisibleDashboard: hasVisibleWindow(in: .shared))
    }

    public func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        guard !isPreview, isReadyForActions else { return nil }
        return services.integration.backgroundDockMenu(
            hasVisibleWindow: hasVisibleWindow(in: sender), locale: services.preferences.language.locale)
    }

    private func hasVisibleWindow(in application: NSApplication) -> Bool {
        application.windows.contains { $0.canBecomeMain && $0.isVisible }
    }
}

@main
enum OctoRunnerEntry {
    @MainActor
    static func main() async {
        #if DEBUG
        if ProcessInfo.processInfo.environment[WorkflowUITestFixture.directoryKey] != nil {
            OctoRunnerWorkflowUITestApp.main()
            return
        }
        #endif
        let arguments = Array(CommandLine.arguments.dropFirst())
        if await AppUpdateHandoff.runInstallerIfRequested(arguments: arguments) { return }
        if AppUpdateHandoff.isStartupRequest(arguments: arguments) {
            guard let update = AppUpdateHandoff.startupUpdate(arguments: arguments) else { return }
            do {
                let store = try OctoRunnerPersistence.openStoreForUpdate(at: OctoRunnerPersistence.defaultStoreURL)
                OctoRunnerAppDelegate.updateStartup = (update, store)
            } catch {
                return
            }
        } else if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" {
            do {
                guard try await AppUpdateHandoff.allowRegularStartup() else { return }
            } catch AppUpdateNotice.inProgress {
                // The installer owns the database and will reopen the app.
                return
            } catch {
                let notice = error as? AppUpdateNotice ?? .recoveryRequired
                NSApplication.shared.activate()
                AppUpdatePresentation.makeAlert(notice, locale: AppPreferencesStore().language.locale).runModal()
                return
            }
        }
        OctoRunnerApp.main()
    }
}

struct OctoRunnerApp: App {
    @NSApplicationDelegateAdaptor(OctoRunnerAppDelegate.self) private var appDelegate

    var body: some Scene {
        let services = appDelegate.services
        let modelContainer = appDelegate.modelContainer
        @Bindable var preferences = services.preferences
        Window("OctoRunner", id: "main-dashboard") {
            if !appDelegate.isPreview && appDelegate.isReadyForActions {
                LocalJobResultsSource { results in
                    MainShellView(
                        historyRateBudget: services.historyRateBudget,
                        accountSession: services.accounts,
                        jobResults: results,
                        supervisor: services.supervisor,
                        launchAgents: services.launchAgents
                    )
                }
                .environment(services.preferences)
                .environment(services.remoteSyncMonitor)
                .environment(services.integration)
                .environment(services.backgroundMonitoring)
                .environment(services.notifications)
                .environment(services.storageMaintenance)
                .environment(\.locale, preferences.language.locale)
                .frame(minWidth: 960, minHeight: 620)
            } else if !appDelegate.isPreview {
                ProgressView().padding(40)
            }
        }
        .modelContainer(modelContainer)
        .windowToolbarStyle(.unified)

        Settings {
            if !appDelegate.isPreview && appDelegate.isReadyForActions {
                SettingsWindowView(accountSession: services.accounts, launchAgents: services.launchAgents)
                    .environment(services.preferences)
                    .environment(services.integration)
                    .environment(services.backgroundMonitoring)
                    .environment(services.notifications)
                    .environment(services.storageMaintenance)
                    .environment(\.locale, preferences.language.locale)
            }
        }
        .modelContainer(modelContainer)

        MenuBarExtra(isInserted: appDelegate.isPreview || !appDelegate.isReadyForActions ? .constant(false) : $preferences.showInMenuBar) {
            MenuBarStatusView(monitor: services.healthMonitor)
                .environment(services.preferences)
                .environment(services.integration)
                .environment(services.notifications)
                .environment(services.storageMaintenance)
                .environment(\.locale, preferences.language.locale)
                .modelContainer(modelContainer)
        } label: {
            RunnerMenuBarJobLabel(monitor: services.healthMonitor)
                .environment(services.preferences)
                .environment(\.locale, preferences.language.locale)
                .modelContainer(modelContainer)
        }
        .menuBarExtraStyle(.window)
    }
}
