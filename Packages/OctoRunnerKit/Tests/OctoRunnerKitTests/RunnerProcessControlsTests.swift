import AppKit
@testable import AppShellFeature
import CoreModels
import Foundation
import RunnerEngine
import SwiftUI
import Testing

@MainActor
struct RunnerProcessControlsTests {
    @Test("An owned runner can start while stopped, drain while busy and restart while idle")
    func availableActions() {
        #expect(RunnerProcessControlAction.available(phase: .stopped, activity: .unknown) == [.start])
        #expect(RunnerProcessControlAction.available(phase: .running, activity: .busy) == [.drain])
        #expect(RunnerProcessControlAction.available(phase: .running, activity: .idle) == [.drain, .restart])
        #expect(RunnerProcessControlAction.available(phase: .draining, activity: .busy).isEmpty)
        #expect(RunnerProcessControlAction.available(phase: .faulted, activity: .unknown) == [.start])
    }

    @Test("Process controls lay out in the runner detail column", arguments: ["de", "en"])
    func compactLayout(language: String) {
        let config = ManagedRunnerConfiguration(runnerID: UUID(), name: "Fixture",
            rootDirectory: URL(fileURLWithPath: "/tmp/synthetic-runner"), mode: .direct)
        let host = NSHostingView(rootView: RunnerProcessControls(configuration: config,
            supervisor: RunnerSupervisorActor()).environment(\.locale, Locale(identifier: language)))
        host.frame = CGRect(x: 0, y: 0, width: 390, height: 125)
        host.layoutSubtreeIfNeeded()
        #expect(host.fittingSize.width <= 390)
        #expect(host.fittingSize.height <= 125)
        #expect(host.bitmapImageRepForCachingDisplay(in: host.bounds) != nil)
    }
}
