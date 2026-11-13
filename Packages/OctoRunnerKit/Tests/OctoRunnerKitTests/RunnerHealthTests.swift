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
            #expect(image.size == NSSize(width: 32, height: 18))
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

    @Test("The OctoRunner mark stays visible and identical beside every status indicator in Light and Dark")
    @MainActor
    func menuBarLogo() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try #require(NSAppearance(named: name))
            var reference: [UInt8]?
            for health in RunnerFleetHealth.allCases {
                let image = RunnerMenuBarIcon.image(for: health)
                var data: Data?
                appearance.performAsCurrentDrawingAppearance { data = image.tiffRepresentation }
                let imageData = try #require(data)
                let bitmap = try #require(NSBitmapImageRep(data: imageData))
                let scale = Double(bitmap.pixelsWide) / image.size.width
                var logo: [UInt8] = []
                var visiblePixels = 0
                for y in 0..<bitmap.pixelsHigh {
                    for x in Int(10 * scale)..<bitmap.pixelsWide {
                        let color = try #require(bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB))
                        if color.alphaComponent > 0.1 { visiblePixels += 1 }
                        for component in [color.redComponent, color.greenComponent, color.blueComponent, color.alphaComponent] {
                            logo.append(UInt8(clamping: Int((component * 255).rounded())))
                        }
                    }
                }
                #expect(visiblePixels > 20)
                if let reference { #expect(logo == reference) }
                else { reference = logo }
            }
        }
    }

    @Test("Differentiate Without Color gives every menu bar status a distinct badge shape")
    @MainActor
    func menuBarAccessibleShapes() throws {
        var patterns = Set<[UInt8]>()
        for health in RunnerFleetHealth.allCases {
            let image = RunnerMenuBarIcon.image(for: health, differentiateWithoutColor: true)
            let data = try #require(image.tiffRepresentation)
            let bitmap = try #require(NSBitmapImageRep(data: data))
            let width = Int(10 * Double(bitmap.pixelsWide) / image.size.width)
            var alpha: [UInt8] = []
            for y in 0..<bitmap.pixelsHigh {
                for x in 0..<width {
                    let color = try #require(bitmap.colorAt(x: x, y: y))
                    alpha.append(UInt8(clamping: Int((color.alphaComponent * 255).rounded())))
                }
            }
            patterns.insert(alpha)
        }
        #expect(patterns.count == RunnerFleetHealth.allCases.count)
        if let path = ProcessInfo.processInfo.environment["OCTORUNNER_MENU_CAPTURE_DIR"] {
            for name in [NSAppearance.Name.aqua, .darkAqua] {
                let appearance = try #require(NSAppearance(named: name))
                var data: Data?
                appearance.performAsCurrentDrawingAppearance {
                    let sheet = NSImage(size: NSSize(width: 320, height: 220), flipped: false) { bounds in
                        NSColor.windowBackgroundColor.setFill()
                        bounds.fill()
                        for (index, health) in RunnerFleetHealth.allCases.enumerated() {
                            let y = CGFloat(index * 42 + 4)
                            RunnerMenuBarIcon.image(for: health).draw(in: NSRect(x: 8, y: y, width: 64, height: 36))
                            RunnerMenuBarIcon.image(for: health, differentiateWithoutColor: true).draw(in: NSRect(x: 88, y: y, width: 64, height: 36))
                            (String(describing: health) as NSString).draw(at: NSPoint(x: 172, y: y + 10), withAttributes: [.font: NSFont.systemFont(ofSize: 14), .foregroundColor: NSColor.labelColor])
                        }
                        return true
                    }
                    data = sheet.tiffRepresentation
                }
                let tiff = try #require(data)
                let bitmap = try #require(NSBitmapImageRep(data: tiff))
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: URL(fileURLWithPath: path).appending(path: "menubar-\(name == .aqua ? "light" : "dark").png"))
            }
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
