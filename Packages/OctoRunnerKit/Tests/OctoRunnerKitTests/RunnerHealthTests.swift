@testable import AppShellFeature
import CoreModels
import Foundation
import AppKit
import Testing

struct RunnerHealthTests {
    let now = Date(timeIntervalSince1970: 1_000)
    let id = UUID()

    @Test("Menu bar health uses distinct symbols and colored non-template images")
    @MainActor
    func menuBarIcon() throws {
        #expect(Set(RunnerFleetHealth.allCases.map(\.symbolName)).count == RunnerFleetHealth.allCases.count)
        for health in RunnerFleetHealth.allCases {
            #expect(NSImage(systemSymbolName: health.symbolName, accessibilityDescription: nil) != nil)
            let image = RunnerMenuBarIcon.image(for: health)
            #expect(!image.isTemplate)
            #expect(image.size == NSSize(width: 18, height: 18))
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            #expect(bitmap.hasAlpha)
            var visible = false
            var colored = false
            for x in 0..<bitmap.pixelsWide {
                for y in 0..<bitmap.pixelsHigh {
                    if let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), color.alphaComponent > 0.1 {
                        visible = true
                        let components = [color.redComponent, color.greenComponent, color.blueComponent]
                        if let low = components.min(), let high = components.max(), high - low > 0.05 { colored = true }
                    }
                }
            }
            #expect(visible)
            if health != .unknown { #expect(colored) }
            #expect(!health.localizedTitle(locale: Locale(identifier: "de")).isEmpty)
        }
    }

    @Test("Fleet status prioritizes failures and never calls missing or stale observations healthy")
    func aggregateHealth() {
        func sample(_ status: RunnerStatus?, age: TimeInterval = 0) -> RunnerHealthObservation {
            RunnerHealthObservation(id: UUID(), name: "Runner", status: status, observedAt: now.addingTimeInterval(-age))
        }
        #expect(RunnerFleetHealth.summarize([], at: now) == .unknown)
        #expect(RunnerFleetHealth.summarize([sample(.idle)], at: now) == .healthy)
        #expect(RunnerFleetHealth.summarize([sample(.idle, age: 61)], at: now) == .unknown)
        #expect(RunnerFleetHealth.summarize([sample(.idle, age: -30)], at: now) == .unknown)
        #expect(RunnerFleetHealth.summarize([sample(.idle), sample(nil)], at: now) == .unknown)
        #expect(RunnerFleetHealth.summarize([sample(.idle), sample(.busy)], at: now) == .busy)
        #expect(RunnerFleetHealth.summarize([sample(.restarting)], at: now) == .busy)
        #expect(RunnerFleetHealth.summarize([sample(.offline), sample(nil)], at: now) == .offline)
        #expect(RunnerFleetHealth.summarize([sample(.offline), sample(.faulted)], at: now) == .faulted)
    }

    @Test("Transitions suppress startup, repeated polls, busy/idle changes, missing samples and removed runners")
    func transitions() {
        var tracker = RunnerHealthTransitionTracker()
        func samples(_ status: RunnerStatus?, age: TimeInterval = 0) -> [RunnerHealthObservation] {
            [RunnerHealthObservation(id: id, name: "Runner", status: status, observedAt: now.addingTimeInterval(-age))]
        }
        #expect(tracker.consume(samples(.idle), at: now).isEmpty)
        #expect(tracker.consume(samples(.busy), at: now).isEmpty)
        #expect(tracker.consume(samples(.offline), at: now).map(\.kind) == [.runnerOffline])
        #expect(tracker.consume(samples(.offline), at: now).isEmpty)
        #expect(tracker.consume(samples(.idle), at: now).map(\.kind) == [.runnerOnline])
        #expect(tracker.consume(samples(.faulted), at: now).map(\.kind) == [.runnerError])
        #expect(tracker.consume(samples(.faulted), at: now).isEmpty)
        #expect(tracker.consume(samples(nil), at: now).isEmpty)
        #expect(tracker.consume(samples(.idle), at: now).isEmpty)
        #expect(tracker.consume(samples(.offline, age: 100), at: now).isEmpty)
        #expect(tracker.consume(samples(.idle), at: now).isEmpty)
        #expect(tracker.consume([], at: now).isEmpty)
        #expect(tracker.consume(samples(.faulted), at: now).isEmpty)
    }

    @Test("Adding notification events preserves existing consent and disabled triggers")
    func notificationPolicyMigration() throws {
        let oldPayload = Data(#"{"enabled":true,"runnerOffline":false,"jobFailure":false,"lowDiskSpace":false,"soundEnabled":false}"#.utf8)
        let restored = try JSONDecoder().decode(NotificationPolicy.self, from: oldPayload)
        #expect(restored.enabled)
        #expect(!restored.runnerOffline && !restored.jobFailure && !restored.lowDiskSpace && !restored.soundEnabled)
        #expect(!restored.runnerOnline && !restored.runnerError)
        var changed = restored
        changed.runnerOnline = true
        changed.runnerError = true
        #expect(try JSONDecoder().decode(NotificationPolicy.self, from: JSONEncoder().encode(changed)) == changed)
    }
}
