import AppKit
@testable import AppShellFeature
import CoreModels
import DesignSystem
import Foundation
import RunnerEngine
import SwiftUI
import Testing

@MainActor
@Suite("Settings system integration", .serialized)
struct SettingsTests {
    @Test("Language selection resolves explicit locales and preserves the system fallback")
    func languageLocale() {
        #expect(AppLanguage.german.locale.identifier == "de")
        #expect(AppLanguage.english.locale.identifier == "en")
        #expect(AppLanguage.system.locale.identifier == Locale.autoupdatingCurrent.identifier)
    }

    @Test("The package ships German and English settings catalog translations")
    func catalogTranslations() throws {
        let germanPath = try #require(Bundle.module.path(forResource: "de", ofType: "lproj"))
        let german = try #require(Bundle(path: germanPath))
        #expect(german.localizedString(forKey: "General", value: nil, table: nil) == "Allgemein")
        #expect(german.localizedString(forKey: "Enable macOS notifications", value: nil, table: nil) == "macOS-Mitteilungen aktivieren")
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
        for language in [AppLanguage.english, .german] {
            for scheme in [ColorScheme.light, .dark] {
                preferences.language = language
                let host = NSHostingView(rootView: SettingsWindowView()
                    .environment(preferences)
                    .environment(services.integration)
                    .environment(services.notifications)
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
                    .environment(services.notifications)
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
