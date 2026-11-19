import AppKit
@testable import AppShellFeature
import CoreModels
import Foundation
import RunnerEngine
import SwiftData
import SwiftUI
import Testing

@MainActor
struct LaunchAgentPanelTests {
    @Test("Only managed and legacy local services are candidates for diagnostics")
    func eligibleRunners() throws {
        let scope = try #require(URL(string: "https://github.com/example/repo"))
        let root = "/tmp/build-runner"
        let runner = RunnerEntity(name: "Build Runner", scopeUrl: scope, workDirectory: URL(filePath: root + "/_work"),
            rootDirectoryPath: root, executionMode: .launchAgent)
        #expect(runner.launchAgentTarget?.label == RunnerServiceLabel.forRunner(named: runner.name))
        runner.serviceLabel = RunnerServiceLabel.forRunner(named: runner.name)
        #expect(runner.launchAgentTarget?.label == runner.serviceLabel)
        runner.executionMode = nil
        #expect(runner.launchAgentTarget != nil)
        runner.executionMode = .direct
        #expect(runner.launchAgentTarget == nil)
        runner.isImportedLocal = true
        #expect(runner.launchAgentTarget == nil)
    }

    @Test("The localized Settings search finds the service diagnostics", arguments: ["en", "de"])
    func search(language: String) {
        #expect(SettingsTab.matching("plist", locale: Locale(identifier: language)) == [.background])
    }

    @Test("The service panel fits the Settings column", arguments: ["en", "de"])
    func layout(language: String) throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let target = RunnerLaunchAgentTarget(name: "Build Runner", rootDirectory: URL(filePath: "/tmp/build-runner"),
            label: "io.octorunner.agent.build-runner")
        let inspector = RunnerLaunchAgentInspector(supervisor: RunnerSupervisorActor(), hasAnotherListener: { _ in true })
        let host = NSHostingView(rootView: RunnerLaunchAgentPanel(runnerID: UUID(), target: target, inspector: inspector)
            .environment(\.locale, Locale(identifier: language)).modelContainer(container))
        host.frame = CGRect(x: 0, y: 0, width: 410, height: 210)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width <= 410)
        #expect(host.fittingSize.height <= 210)
        #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
    }
}
