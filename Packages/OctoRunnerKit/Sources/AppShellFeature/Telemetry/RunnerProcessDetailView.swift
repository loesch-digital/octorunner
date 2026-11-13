import DesignSystem
import SwiftUI
import TelemetryKit

struct RunnerProcessDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let process: InspectedRunnerProcess

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Process Details", bundle: .module).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                Spacer()
                Button { dismiss() } label: { Text("Close", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Close", bundle: .module))
                    .accessibilityHint(Text("Close the process details.", bundle: .module))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent { Text(verbatim: process.runner.name) } label: { Text("Runner", bundle: .module) }
                    LabeledContent("PID", value: String(process.id.pid))
                    LabeledContent { Text(process.id.startedAt, format: .dateTime.year().month().day().hour().minute().second()) }
                        label: { Text("Started", bundle: .module) }
                    LabeledContent { Text(process.sampledAt, format: .dateTime.hour().minute().second()) }
                        label: { Text("Measured at", bundle: .module) }
                    LabeledContent { Text(String(process.metadata.parentPID)) } label: { Text("Parent PID", bundle: .module) }
                    LabeledContent { Text(String(process.metadata.userID)) } label: { Text("User ID", bundle: .module) }
                    LabeledContent { Text(Duration.seconds(process.runtimeSeconds), format: .time(pattern: .hourMinuteSecond)) }
                        label: { Text("Runtime", bundle: .module) }
                    LabeledContent {
                        if let cpu = process.cpuPercent { Text(cpu / 100, format: .percent.precision(.fractionLength(1))) }
                        else { Text("—") }
                    } label: { Text("CPU", bundle: .module) }
                    LabeledContent {
                        if let bytes = process.metadata.residentBytes { Text(Int64(clamping: bytes), format: .byteCount(style: .memory)) }
                        else { Text("—") }
                    } label: { Text("Resident memory", bundle: .module) }
                    Text("Executable", bundle: .module).font(.headline)
                    Text(verbatim: process.metadata.executablePath).font(.callout.monospaced()).fixedSize(horizontal: false, vertical: true)
                    Text("This is a snapshot. Arguments and environment variables are not read or displayed.", bundle: .module)
                        .foregroundStyle(OctoTheme.secondaryText)
                }
                .textSelection(.enabled)
            }
        }
        .padding(20)
        .frame(minWidth: 480, idealWidth: 620, minHeight: 360, idealHeight: 480)
        .background(OctoTheme.surfaceLowest)
    }
}
