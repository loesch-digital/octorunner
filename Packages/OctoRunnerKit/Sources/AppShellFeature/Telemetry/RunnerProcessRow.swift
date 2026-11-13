import DesignSystem
import SwiftUI
import TelemetryKit

struct RunnerProcessRow: View {
    let process: InspectedRunnerProcess
    let isTerminating: Bool
    let inspect: (InspectedRunnerProcess) -> Void
    let terminate: (InspectedRunnerProcess) -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                identity.frame(minWidth: 160, maxWidth: .infinity, alignment: .leading)
                metrics
                actions
            }
            VStack(alignment: .leading, spacing: 12) {
                identity
                metrics
                actions
            }
        }
        .padding(12)
        .background(OctoTheme.surfaceLowest, in: .rect(cornerRadius: 8))
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(verbatim: process.name).font(.headline).lineLimit(2)
            Text(verbatim: process.runner.name).font(.callout).foregroundStyle(OctoTheme.secondaryText).lineLimit(2)
            Text("PID \(process.id.pid)").font(.callout.monospaced())
        }
    }

    private var metrics: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("CPU", bundle: .module).font(.caption).foregroundStyle(OctoTheme.secondaryText)
                if let cpu = process.cpuPercent { Text(cpu / 100, format: .percent.precision(.fractionLength(1))).monospacedDigit() }
                else { Text("—") }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Resident memory", bundle: .module).font(.caption).foregroundStyle(OctoTheme.secondaryText)
                if let bytes = process.metadata.residentBytes { Text(Int64(clamping: bytes), format: .byteCount(style: .memory)).monospacedDigit() }
                else { Text("—") }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Runtime", bundle: .module).font(.caption).foregroundStyle(OctoTheme.secondaryText)
                Text(Duration.seconds(process.runtimeSeconds), format: .time(pattern: .hourMinuteSecond)).monospacedDigit()
            }
        }
    }

    private var actions: some View {
        HStack {
            Button { inspect(process) } label: { Text("Inspect", bundle: .module) }
                .accessibilityLabel(Text("Inspect", bundle: .module))
                .accessibilityHint(Text("Show the process identity, executable and latest measurements.", bundle: .module))
            Button(role: .destructive) { terminate(process) } label: { Text("Terminate…", bundle: .module) }
                .disabled(isTerminating)
                .accessibilityLabel(Text("Terminate…", bundle: .module))
                .accessibilityHint(Text("Review and confirm a SIGTERM request for this process.", bundle: .module))
        }
        .buttonStyle(.bordered)
    }
}
