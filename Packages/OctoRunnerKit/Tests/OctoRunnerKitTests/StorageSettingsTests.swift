import AppKit
@testable import AppShellFeature
import CoreModels
import SwiftUI
import Testing

@MainActor
struct StorageSettingsTests {
    @Test("Cache and Storage is a real sixth settings category and is searchable in both languages")
    func categoryExists() {
        #expect(SettingsTab.allCases.count == 6)
        #expect(SettingsTab.matching("cache storage", locale: Locale(identifier: "en")).count == 1)
        #expect(SettingsTab.matching("speicher", locale: Locale(identifier: "de")).contains(.storage))
    }
}
