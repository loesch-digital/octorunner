import CoreModels
import SwiftUI

public struct RunnerStatusBadge: View {
    private let status: RunnerStatus

    public init(status: RunnerStatus) {
        self.status = status
    }

    public var body: some View {
        let color = OctoTheme.statusColor(for: status)
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(status.badgeTitle)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(color.opacity(0.14), in: .rect(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(color.opacity(0.35), lineWidth: 1)
        }
    }
}
