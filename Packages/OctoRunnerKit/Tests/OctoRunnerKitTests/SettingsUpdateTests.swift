import AppKit
import CoreModels
import SwiftData
import SwiftUI
import Foundation
import GitHubAPI
import Testing
@testable import AppShellFeature

@MainActor
struct SettingsUpdateTests {
    @Test("Settings update checking is manual and uses the actual supplied bundle version")
    func manualCheck() async {
        let checker = SettingsReleaseFixture()
        let model = SettingsUpdateController(currentVersion: "0.5.0-beta.2", checker: checker.check)
        #expect(await checker.versions.isEmpty)
        #expect(model.info == nil && !model.isChecking && !model.checkFailed)
        #expect(model.currentVersion == "0.5.0-beta.2")
        await model.checkForUpdates()
        #expect(await checker.versions == ["0.5.0-beta.2"])
        #expect(model.info?.latestVersion == "0.5.0")
        #expect(!model.isChecking && !model.checkFailed)
    }

    @Test("A failed update check cannot appear as an up-to-date result")
    func failedCheck() async {
        let model = SettingsUpdateController(currentVersion: "0.5.0", checker: { _ in throw URLError(.notConnectedToInternet) })
        await model.checkForUpdates()
        #expect(model.checkFailed)
        #expect(model.info == nil && !model.isChecking)
    }

    @Test("Explicit cancellation errors are not shown as update failures")
    func cancellationError() async {
        let model = SettingsUpdateController(currentVersion: "0.5.0", checker: { _ in throw CancellationError() })
        await model.checkForUpdates()
        #expect(!model.checkFailed && model.info == nil && !model.isChecking)
    }

    @Test("Update settings are searchable and translated in German and English")
    func updateSettingsLocalizationAndSearch() {
        #expect(AppLocalization.string("Versions and updates", locale: Locale(identifier: "de")) == "Versionen und Updates")
        #expect(AppLocalization.string("Check for updates", locale: Locale(identifier: "de")) == "Nach Updates suchen")
        #expect(AppLocalization.string("Update check failed. Try again.", locale: Locale(identifier: "de")) == "Update-Prüfung fehlgeschlagen. Versuche es erneut.")
        for (term, language) in [("App version", "en"), ("Update channel", "en"), ("App-Version", "de"), ("Update-Kanal", "de")] {
            #expect(SettingsTab.matching(term, locale: Locale(identifier: language)) == [.general])
        }
        #expect(SettingsTab.matching("updates", locale: Locale(identifier: "en")) == [.general])
        #expect(SettingsTab.matching("Updates", locale: Locale(identifier: "de")) == [.general])
    }

    @Test("Cancellation discards a late update response and concurrent clicks cannot start a second check")
    func cancelledCheck() async {
        let (ready, signal) = AsyncStream.makeStream(of: Void.self)
        let checker = SettingsReleaseFixture(ready: signal)
        let model = SettingsUpdateController(currentVersion: "0.5.0", checker: checker.check)
        let task = Task {
            defer { signal.finish() }
            await model.checkForUpdates()
        }
        for await _ in ready { break }
        #expect(model.isChecking)
        await model.checkForUpdates()
        #expect(await checker.versions.count == 1)
        task.cancel()
        await checker.release()
        await task.value
        #expect(model.info == nil && !model.checkFailed && !model.isChecking)
    }

    @Test("Version settings remain compact with many runners across sizes, languages and appearances")
    func versionCardRendering() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        for index in 0..<100 {
            container.mainContext.insert(RunnerEntity(name: "runner-\(index)",
                scopeUrl: URL(string: "https://github.com/example/repo")!,
                workDirectory: URL(filePath: "/tmp/runner-\(index)/_work"),
                runnerVersion: index.isMultiple(of: 3) ? nil : "2.329.0"))
        }
        try container.mainContext.save()
        for language in ["de", "en"] {
            for width in [620.0, 960.0] {
                for scheme in [ColorScheme.light, .dark] {
                    let model = SettingsUpdateController(currentVersion: "0.5.0", checker: { _ in
                        Issue.record("Rendering must not contact GitHub")
                        throw URLError(.cancelled)
                    })
                    let host = NSHostingView(rootView: SettingsUpdateCard(controller: model)
                        .modelContainer(container)
                        .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme)
                        .padding().frame(width: width))
                    host.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
                    host.frame = CGRect(x: 0, y: 0, width: width, height: 600)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
                    window.isReleasedWhenClosed = false
                    window.contentView = host
                    for _ in 0..<10 { await Task.yield() }
                    host.layoutSubtreeIfNeeded()
                    let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    #expect(host.fittingSize.height <= 600)
                    #expect(!model.isChecking && model.info == nil && !model.checkFailed)
                    window.contentView = nil
                    window.close()
                    if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                        try #require(bitmap.representation(using: .png, properties: [:])).write(to:
                            URL(filePath: path).appending(path: "settings-updates-\(language)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                    }
                }
            }
        }
    }

    @Test("Engine versions are deduplicated, naturally sorted, and never invented for unknown runners")
    func installedEngineVersions() {
        let summary = InstalledRunnerVersionSummary(["2.10.0", "2.9.0", " 2.10.0 ", nil, " "])
        #expect(summary.versions == ["2.9.0", "2.10.0"])
        #expect(summary.hasUnknownVersion)
        #expect(summary.runnerCount == 5)
        let empty = InstalledRunnerVersionSummary([])
        #expect(empty.versions.isEmpty && !empty.hasUnknownVersion && empty.runnerCount == 0)
    }
}

private actor SettingsReleaseFixture {
    private(set) var versions: [String] = []
    let ready: AsyncStream<Void>.Continuation?
    private var completion: CheckedContinuation<Void, Never>?

    init(ready: AsyncStream<Void>.Continuation? = nil) { self.ready = ready }

    func check(_ version: String) async throws -> AppUpdateInfo {
        versions.append(version)
        if let ready, versions.count == 1 {
            await withCheckedContinuation { completion in
                self.completion = completion
                ready.yield(())
                ready.finish()
            }
        }
        return AppUpdateInfo(currentVersion: version, latestVersion: "0.5.0", releaseTitle: "OctoRunner", releaseNotes: "",
            releasePageURL: URL(string: "https://github.com/loesch-digital/octorunner/releases/tag/v0.5.0")!,
            zipDownloadURL: nil, isUpdateAvailable: version != "0.5.0")
    }

    func release() { completion?.resume(); completion = nil }
}
