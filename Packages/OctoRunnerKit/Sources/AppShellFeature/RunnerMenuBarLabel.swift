import SwiftUI

public struct RunnerMenuBarLabel: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @State private var health: RunnerFleetHealth = .unknown
    private let monitor: RunnerHealthMonitor

    public init(monitor: RunnerHealthMonitor) { self.monitor = monitor }

    public var body: some View {
        Image(nsImage: RunnerMenuBarIcon.image(for: health, differentiateWithoutColor: differentiateWithoutColor))
            .id(colorScheme)
            .accessibilityLabel("OctoRunner: \(health.localizedTitle(locale: locale))")
            .help("OctoRunner: \(health.localizedTitle(locale: locale))")
            // TimelineView inside the MenuBarExtra label can continuously invalidate
            // its AppKit status image during scene startup and starve the main loop.
            // A cancellable task refreshes on new samples and expires stale samples.
            .task(id: monitor.observations) {
                while !Task.isCancelled {
                    health = monitor.health(at: .now)
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return }
                }
            }
    }
}
