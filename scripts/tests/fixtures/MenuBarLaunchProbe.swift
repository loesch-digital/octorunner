// Isolated native Scene test of the actual production label, with constant input.
// No preferences, SwiftData, Keychain, runner processes or external folders.
import AppKit
import Foundation
import Observation
import SwiftUI

@MainActor @Observable
public final class RunnerHealthMonitor {
    public var observations: [Int] = []
    public init() {}
    public func health(at date: Date) -> RunnerFleetHealth { .unknown }
}
public enum RunnerFleetHealth {
    case unknown
    public func localizedTitle(locale: Locale) -> String { "Unknown" }
}
@MainActor
public enum RunnerMenuBarIcon {
    public static func image(for health: RunnerFleetHealth, differentiateWithoutColor: Bool = false) -> NSImage {
        NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)!
    }
}

@main
struct MenuBarLaunchProbe: App {
    @State private var monitor = RunnerHealthMonitor()

    init() {
        // This callback cannot run if MenuBarExtra initialization monopolizes the main thread.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            do {
                try Data("responsive".utf8).write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
                exit(0)
            } catch { exit(2) }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Isolated launch probe")
        } label: {
            RunnerMenuBarLabel(monitor: monitor)
        }
        .menuBarExtraStyle(.window)
    }
}
