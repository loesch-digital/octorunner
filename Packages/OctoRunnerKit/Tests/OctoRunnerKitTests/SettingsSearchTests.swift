@testable import AppShellFeature
import Foundation
import Testing

struct SettingsSearchTests {
    @Test("Settings search finds actual localized options instead of runner names")
    func localizedOptions() {
        #expect(SettingsTab.matching("  ", locale: Locale(identifier: "en")) == SettingsTab.allCases)
        #expect(SettingsTab.matching("notification sound", locale: Locale(identifier: "en")) == [.notifications])
        #expect(SettingsTab.matching("Sprache", locale: Locale(identifier: "de")) == [.general])
        #expect(SettingsTab.matching("PATH", locale: Locale(identifier: "de")) == [.background])
        #expect(SettingsTab.matching("restart delay", locale: Locale(identifier: "en")) == [.failover])
        #expect(SettingsTab.matching("token", locale: Locale(identifier: "de")) == [.auth])
        #expect(SettingsTab.matching("no-such-setting-1234", locale: Locale(identifier: "en")).isEmpty)
    }
}
