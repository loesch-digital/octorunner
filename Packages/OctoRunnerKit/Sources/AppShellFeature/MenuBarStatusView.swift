import CoreModels
import DesignSystem
import SwiftData
import SwiftUI

public struct MenuBarStatusView: View {
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @Environment(\.openWindow) private var openWindow

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "infinity.circle.fill")
                    .foregroundStyle(OctoTheme.accentBlue)
                Text("OctoRunner Desktop")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(runners.count) Runners")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Divider()

            if runners.isEmpty {
                Text("No local runners configured.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(runners) { runner in
                    HStack {
                        Text(runner.name)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                        Spacer()
                        RunnerStatusBadge(status: runner.status)
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Dashboard", systemImage: "macwindow") {
                    openWindow(id: "main-dashboard")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                Spacer()
                Button("Quit", systemImage: "power", role: .destructive) {
                    NSApplication.shared.terminate(nil)
                }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 310)
    }
}
