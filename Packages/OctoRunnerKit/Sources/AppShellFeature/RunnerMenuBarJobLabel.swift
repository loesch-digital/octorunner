import DesignSystem
import SwiftUI

public struct RunnerMenuBarJobLabel: View {
    @Environment(\.locale) private var locale
    private let monitor: RunnerHealthMonitor

    public init(monitor: RunnerHealthMonitor) { self.monitor = monitor }

    public var body: some View {
        LocalJobResultsSource { results in
            HStack(spacing: 3) {
                RunnerMenuBarLabel(monitor: monitor)
                if !results.unreviewedFailures.isEmpty {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(OctoTheme.errorRed)
                        .accessibilityLabel(JobFailureNotice.title(results.unreviewedFailures.count, locale: locale))
                        .help(JobFailureNotice.title(results.unreviewedFailures.count, locale: locale))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
