import AppKit
@testable import AppShellFeature
import CoreModels
import DesignSystem
import Foundation
import RunnerEngine
import SwiftUI
import SwiftData
import Testing

@MainActor
@Suite("Settings system integration", .serialized)
struct SettingsTests {
    private static var retainedContainers: [ModelContainer] = []

    @Test("Settings cards render every category at narrow and wide widths in both languages and appearances")
    func settingsCardsRendering() throws {
        let name = "octorunner-settings-cards-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let services = AppServices(preferences: AppPreferencesStore(defaults: defaults),
            loginService: SettingsLoginService(), notificationClient: SettingsNotificationClient())
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let pages: [(String, AnyView)] = [
            ("general", AnyView(GeneralSettingsTab())),
            ("background", AnyView(BackgroundSettingsTab())),
            ("failover", AnyView(FailoverSettingsTab())),
            ("storage", AnyView(StorageSettingsTab())),
            ("auth", AnyView(SecurityTokenSettingsTab(accountSession: services.accounts))),
            ("notifications", AnyView(AlertsSettingsTab()))
        ]
        for (page, view) in pages {
            for language in ["de", "en"] {
                for width in [620.0, 960.0] {
                    for scheme in [ColorScheme.light, .dark] {
                        let host = NSHostingView(rootView: view
                            .environment(services.preferences).environment(services.integration)
                            .environment(services.notifications).environment(services.storageMaintenance).modelContainer(container)
                            .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme)
                            .frame(width: width, height: 600))
                        host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                        host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
                        host.layoutSubtreeIfNeeded()
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        #expect(host.fittingSize.width <= width)
                        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
                        if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                            try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                                URL(fileURLWithPath: path).appending(path: "settings-page-\(page)-\(language)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                        }
                    }
                }
            }
        }
        #expect(!services.preferences.launchAtLogin && !services.preferences.notificationPolicy.enabled)
    }

    @Test("The main sidebar offers general app settings rather than a runner-count category")
    func mainSettingsDestination() {
        #expect(SidebarSection.launchdSettings.title == "Settings")
        #expect(SidebarSection.launchdSettings.systemImage == "gearshape")
    }

    @Test("App settings render inside the main window with the same shared system services")
    func mainSettingsRender() throws {
        let name = "octorunner-main-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let services = AppServices(preferences: AppPreferencesStore(defaults: defaults),
            loginService: SettingsLoginService(), notificationClient: SettingsNotificationClient())
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let host = NSHostingView(rootView: MainShellView(section: .launchdSettings, accountSession: services.accounts)
            .environment(services.preferences).environment(services.integration).environment(services.notifications).environment(services.storageMaintenance)
            .modelContainer(container))
        host.frame = CGRect(x: 0, y: 0, width: 960, height: 620)
        host.layoutSubtreeIfNeeded()
        #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
        #expect(!services.preferences.launchAtLogin && !services.preferences.notificationPolicy.enabled)
    }
    @Test("Language selection resolves explicit locales and preserves the system fallback")
    func languageLocale() {
        #expect(AppLanguage.german.locale.identifier == "de")
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.system.locale.identifier == Locale.autoupdatingCurrent.identifier)
    }

    @Test("The app module resolves its German and English catalog translations")
    func catalogTranslations() {
        // Exercise the production bundle lookup. Bundle.module here belongs to
        // the test target as soon as it has its own fixture resources.
        #expect(RunnerFleetHealth.healthy.localizedTitle(locale: Locale(identifier: "de")) == "Alle lokalen Runner aktiv")
        #expect(RunnerFleetHealth.unknown.localizedTitle(locale: Locale(identifier: "de")) == "Runner-Status unbekannt")
        #expect(RunnerFleetHealth.healthy.localizedTitle(locale: Locale(identifier: "en")) == "All local runners active")
        #expect(AppLocalization.string("General", locale: Locale(identifier: "de")) == "Allgemein")
        #expect(AppLocalization.string("Enable macOS notifications", locale: Locale(identifier: "de")) == "macOS-Mitteilungen aktivieren")
    }

    @Test("Settings windows are never mistaken for the dashboard")
    func settingsWindowIdentity() {
        #expect(DashboardWindowCoordinator.shouldOpenNewWindow(visibleWindowTitles: ["OctoRunner Settings"]))
        #expect(!DashboardWindowCoordinator.isDashboardWindow(title: "OctoRunner Settings", identifier: "settings"))
        #expect(DashboardWindowCoordinator.isDashboardWindow(title: "OctoRunner", identifier: nil))
        #expect(DashboardWindowCoordinator.isDashboardWindow(title: "", identifier: "main-dashboard"))
    }

    @Test("Shared settings services do not register login items or request notification access on construction")
    func servicesHaveNoStartupPermissionEffects() async throws {
        let name = "octorunner-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let login = SettingsLoginService()
        let notifications = SettingsNotificationClient()
        let services = AppServices(preferences: AppPreferencesStore(defaults: defaults), loginService: login, notificationClient: notifications)
        #expect(!services.preferences.notificationPolicy.enabled)
        #expect(await login.registrations == 0)
        #expect(await notifications.permissionRequests == 0)
    }

    @Test("Settings render in both languages and appearances without changing saved preferences")
    func settingsRendering() throws {
        let name = "octorunner-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let services = AppServices(preferences: preferences, loginService: SettingsLoginService(), notificationClient: SettingsNotificationClient())
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        for language in [AppLanguage.english, .german] {
            for scheme in [ColorScheme.light, .dark] {
                preferences.language = language
                let host = NSHostingView(rootView: SettingsWindowView()
                    .modelContainer(container)
                    .environment(preferences)
                    .environment(services.integration)
                    .environment(services.notifications).environment(services.storageMaintenance)
                    .environment(\.locale, language.locale)
                    .environment(\.colorScheme, scheme))
                host.frame = NSRect(x: 0, y: 0, width: 680, height: 520)
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.height > 0)
                #expect(host.fittingSize.width <= 680)
                #expect(!preferences.launchAtLogin)
                #expect(!preferences.notificationPolicy.enabled)
                let alerts = NSHostingView(rootView: AlertsSettingsTab()
                    .environment(preferences)
                    .environment(services.notifications).environment(services.storageMaintenance)
                    .environment(\.locale, language.locale)
                    .environment(\.colorScheme, scheme))
                alerts.frame = NSRect(x: 0, y: 0, width: 680, height: 520)
                alerts.layoutSubtreeIfNeeded()
                // Form's unconstrained fittingSize is an ideal width, not its
                // minimum. Verify actual rendering at the constrained viewport.
                let bitmap = try #require(alerts.bitmapImageRepForCachingDisplay(in: alerts.bounds))
                alerts.cacheDisplay(in: alerts.bounds, to: bitmap)
                #expect(bitmap.pixelsWide > 0)
                #expect(bitmap.pixelsHigh > 0)
                #expect(try #require(bitmap.representation(using: .png, properties: [:])).count > 0)
                #expect(alerts.fittingSize.height > 0)
            }
        }
    }

    @Test("Settings warning and error text retain AA contrast in Light and Dark")
    func settingsStatusContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                for color in [OctoTheme.warningOrange, OctoTheme.errorRed] {
                    let foreground = NSColor(color).usingColorSpace(.sRGB)!
                    let background = NSColor(OctoTheme.surface).usingColorSpace(.sRGB)!
                    let ratio = OctoTheme.wcagContrastRatio(
                        foregroundRGB: (foreground.redComponent, foreground.greenComponent, foreground.blueComponent),
                        backgroundRGB: (background.redComponent, background.greenComponent, background.blueComponent))
                    #expect(ratio >= 4.5, "Appearance: \(name.rawValue), ratio: \(ratio), foreground: \(foreground), background: \(background)")
                }
            }
        }
    }

    @Test("Settings explanations retain AA contrast on card and page backgrounds in Light and Dark")
    func settingsSupportingTextContrast() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                for surface in [OctoTheme.surface, OctoTheme.surfaceLowest] {
                    let foreground = NSColor(OctoTheme.secondaryText).usingColorSpace(.sRGB)!
                    let background = NSColor(surface).usingColorSpace(.sRGB)!
                    let alpha = foreground.alphaComponent
                    let ratio = OctoTheme.wcagContrastRatio(
                        foregroundRGB: (
                            foreground.redComponent * alpha + background.redComponent * (1 - alpha),
                            foreground.greenComponent * alpha + background.greenComponent * (1 - alpha),
                            foreground.blueComponent * alpha + background.blueComponent * (1 - alpha)),
                        backgroundRGB: (background.redComponent, background.greenComponent, background.blueComponent))
                    #expect(ratio >= 4.5)
                }
            }
        }
    }

    @Test("Runner defaults settings render without registering login items or changing policies")
    func runnerDefaultsRendering() async throws {
        let name = "octorunner-settings-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let login = SettingsLoginService()
        let integration = AppIntegrationController(preferences: preferences, loginService: login)
        let original = preferences.runtimePolicy
        for language in [AppLanguage.english, .german] {
            for scheme in [ColorScheme.light, .dark] {
                let background = NSHostingView(rootView: BackgroundSettingsTab()
                    .environment(preferences).environment(integration)
                    .environment(\.locale, language.locale).environment(\.colorScheme, scheme))
                let failover = NSHostingView(rootView: FailoverSettingsTab()
                    .environment(preferences)
                    .environment(\.locale, language.locale).environment(\.colorScheme, scheme))
                for host in [background as NSView, failover as NSView] {
                    host.frame = NSRect(x: 0, y: 0, width: 680, height: 520)
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    #expect(try #require(bitmap.representation(using: .png, properties: [:])).count > 0)
                }
            }
        }
        #expect(preferences.runtimePolicy == original)
        #expect(await login.registrations == 0)
    }
}

private actor SettingsLoginService: LoginItemServicing {
    private(set) var registrations = 0
    func status() -> LoginItemState { .disabled }
    func setEnabled(_ enabled: Bool) { registrations += 1 }
}

private actor SettingsNotificationClient: AppNotificationClient {
    private(set) var permissionRequests = 0
    func authorizationStatus() -> NotificationAuthorizationState { .notDetermined }
    func requestAuthorization() -> Bool { permissionRequests += 1; return false }
    func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) {}
}
