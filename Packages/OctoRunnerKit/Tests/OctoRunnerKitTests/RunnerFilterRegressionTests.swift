import AppKit
@testable import AppShellFeature
import CoreModels
import Foundation
import SwiftUI
import Testing

@MainActor
struct RunnerFilterRegressionTests {
    @Test("Audit runner choices include registered and removed runners without duplicates or app-wide entries")
    func runnerChoices() {
        let choices = AuditRunnerOptions.names(registered: ["mac-2", "mac-1", "mac-2"], historical: [nil, "mac-1", "removed-runner", ""])
        #expect(choices == ["mac-1", "mac-2", "removed-runner"])
        #expect(AuditRunnerOptions.names(registered: [], historical: [nil, ""]).isEmpty)
    }

    @Test("Empty runner views distinguish registration, status filters and search")
    func emptyStates() {
        #expect(RunnerPoolEmptyState(registeredCount: 0, section: .allRunners, search: "") == .unregistered)
        #expect(RunnerPoolEmptyState(registeredCount: 1, section: .failedFaulted, search: "") == .noFaulted)
        #expect(RunnerPoolEmptyState(registeredCount: 1, section: .activeDaemons, search: "") == .noActive)
        #expect(RunnerPoolEmptyState(registeredCount: 1, section: .allRunners, search: "missing") == .noSearchMatches)
        #expect(RunnerPoolEmptyState(registeredCount: 1, section: .failedFaulted, search: "missing") == .noSearchMatches)
        #expect(RunnerPoolEmptyState(registeredCount: 0, section: .failedFaulted, search: "missing") == .unregistered)
    }
}
