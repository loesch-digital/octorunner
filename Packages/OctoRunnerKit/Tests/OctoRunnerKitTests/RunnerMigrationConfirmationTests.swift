import AppKit
@testable import AppShellFeature
import Foundation
import SwiftUI
import Testing

@MainActor
struct RunnerMigrationConfirmationTests {
    @Test("Migration confirmation fits the narrow Settings sheet in English and German", arguments: ["en", "de"])
    func laysOutConfirmation(language: String) {
        let host = NSHostingView(rootView: RunnerMigrationConfirmation(
            runnerName: "Mac mini Build Runner",
            account: "build-team",
            source: URL(filePath: "/Users/fixture/Documents/Development/Current Build Runner"),
            destination: URL(filePath: "/Users/fixture/Library/Application Support/OctoRunner/Managed Build Runner"),
            scope: URL(string: "https://github.com/example/runner-repo")!,
            group: "Build runners",
            labels: ["self-hosted", "macOS", "ARM64", "xcode", "fastlane"],
            launchAgent: language == "de",
            onCancel: {}, onConfirm: {}
        )
            .environment(\.locale, Locale(identifier: language))
            .environment(\.colorScheme, language == "de" ? .dark : .light))
        host.frame = CGRect(x: 0, y: 0, width: 460, height: 510)
        host.layoutSubtreeIfNeeded()

        #expect(host.fittingSize.width <= 460)
        #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
    }
}
