import CoreModels
import SwiftUI

public struct RunnerStatusBadge: View {
    private let status: RunnerStatus

    public init(status: RunnerStatus) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(OctoTheme.statusColor(for: status))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)

            Text(status.badgeTitle)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(OctoTheme.statusColor(for: status))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            OctoTheme.statusColor(for: status).opacity(0.14),
            in: .capsule
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Runner Status")
        .accessibilityValue(status.badgeTitle)
    }
}
