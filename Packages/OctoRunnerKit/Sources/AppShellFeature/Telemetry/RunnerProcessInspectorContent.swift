import DesignSystem
import SwiftUI
import TelemetryKit

struct RunnerProcessInspectorContent: View {
    let processes: [InspectedRunnerProcess]
    let targets: [RunnerProcessTarget]
    @Binding var selectedRunnerID: UUID?
    let samplingFailed: Bool
    let isTerminating: Bool
    let inspect: (InspectedRunnerProcess) -> Void
    let terminate: (InspectedRunnerProcess) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ViewThatFits(in: .horizontal) {
                HStack { heading; Spacer(); runnerFilter }
                VStack(alignment: .leading, spacing: 12) { heading; runnerFilter }
            }
            Text("Only identifiable runner processes and their child processes are shown. CPU: 100% equals one fully used core. Arguments and environment are excluded.", bundle: .module)
                .font(.callout).foregroundStyle(OctoTheme.secondaryText).fixedSize(horizontal: false, vertical: true)
            if samplingFailed {
                Label { Text("Process information is unavailable. Try refreshing telemetry.", bundle: .module) }
                    icon: { Image(systemName: "exclamationmark.triangle").accessibilityHidden(true) }
                    .foregroundStyle(OctoTheme.warningOrange)
            } else if processes.isEmpty {
                ContentUnavailableView {
                    Label { Text("No matching runner processes", bundle: .module) } icon: { Image(systemName: "terminal") }
                } description: {
                    Text("The runner may be stopped, its process information unavailable, or its folder assignment ambiguous. Choose another runner or refresh.", bundle: .module)
                }
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(processes) { process in
                        RunnerProcessRow(process: process, isTerminating: isTerminating, inspect: inspect, terminate: terminate)
                    }
                }
            }
        }
        .padding(16)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(OctoTheme.outlineVariant.opacity(0.45), lineWidth: 1) }
    }

    private var heading: some View {
        Text("Processes by Runner", bundle: .module).font(.headline).accessibilityAddTraits(.isHeader)
    }

    private var runnerFilter: some View {
        Picker(selection: $selectedRunnerID) {
            Text("All runners", bundle: .module).tag(Optional<UUID>.none)
            ForEach(targets) { runner in Text(verbatim: runner.name).tag(Optional(runner.id)) }
        } label: { Text("Runner", bundle: .module) }
        .accessibilityLabel(Text("Process runner filter", bundle: .module))
        .accessibilityHint(Text("Show processes belonging to the selected runner.", bundle: .module))
    }
}
