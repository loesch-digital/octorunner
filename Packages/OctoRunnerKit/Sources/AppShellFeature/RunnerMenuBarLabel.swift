import SwiftUI

public struct RunnerMenuBarLabel: View {
    @Environment(\.locale) private var locale
    @Environment(\.colorScheme) private var colorScheme
    private let monitor: RunnerHealthMonitor

    public init(monitor: RunnerHealthMonitor) { self.monitor = monitor }

    public var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { context in
            let health = monitor.health(at: context.date)
            Image(nsImage: RunnerMenuBarIcon.image(for: health))
                .id(colorScheme)
                .accessibilityLabel("OctoRunner: \(health.localizedTitle(locale: locale))")
                .help("OctoRunner: \(health.localizedTitle(locale: locale))")
        }
    }
}
