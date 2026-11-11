import CoreModels
import Foundation
import Testing

@MainActor
struct AppPreferencesTests {
    @Test("Preferences survive recreating the store without leaking into another defaults suite")
    func persistsAcrossLaunches() throws {
        let name = "octorunner-preferences-test-\(UUID().uuidString)"
        let otherName = "octorunner-preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        let other = try #require(UserDefaults(suiteName: otherName))
        defer {
            defaults.removePersistentDomain(forName: name)
            other.removePersistentDomain(forName: otherName)
        }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.language = .german
        preferences.launchAtLogin = true
        preferences.showInMenuBar = false
        preferences.hideDockIconWhenClosed = false
        preferences.maxConcurrentRunners = 8
        preferences.inheritHostPath = false
        preferences.diskAutoPruningEnabled = true
        preferences.pruneWorkspacesOlderThanDays = 14

        let restored = AppPreferencesStore(defaults: defaults)
        #expect(restored.language == .german)
        #expect(restored.launchAtLogin)
        #expect(!restored.showInMenuBar)
        #expect(!restored.hideDockIconWhenClosed)
        #expect(restored.maxConcurrentRunners == 8)
        #expect(!restored.inheritHostPath)
        #expect(restored.diskAutoPruningEnabled)
        #expect(restored.pruneWorkspacesOlderThanDays == 14)
        #expect(AppPreferencesStore(defaults: other).language == .system)
    }

    @Test("Fresh preferences do not opt users into login registration or automatic deletion")
    func safeDefaults() throws {
        let name = "octorunner-preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        #expect(!preferences.launchAtLogin)
        #expect(!preferences.diskAutoPruningEnabled)
        #expect(preferences.showInMenuBar)
    }

    @Test("Invalid persisted preferences and numeric input fall back to safe supported values")
    func validatesInput() throws {
        let name = "octorunner-preferences-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("not-a-language", forKey: "preferences.language")
        defaults.set(-20, forKey: "preferences.maxConcurrentRunners")
        defaults.set("not-an-integer", forKey: "preferences.pruneWorkspacesOlderThanDays")
        let preferences = AppPreferencesStore(defaults: defaults)
        #expect(preferences.language == .system)
        #expect(preferences.maxConcurrentRunners == 1)
        #expect(preferences.pruneWorkspacesOlderThanDays == 7)
        preferences.maxConcurrentRunners = 100_000
        preferences.pruneWorkspacesOlderThanDays = -1
        #expect(preferences.maxConcurrentRunners == 64)
        #expect(preferences.pruneWorkspacesOlderThanDays == 1)
        #expect(AppPreferencesStore(defaults: defaults).maxConcurrentRunners == 64)
    }
}
