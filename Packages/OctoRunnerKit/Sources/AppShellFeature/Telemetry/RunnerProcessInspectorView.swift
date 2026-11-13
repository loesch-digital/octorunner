import DesignSystem
import SwiftData
import SwiftUI
import TelemetryKit

struct RunnerProcessInspectorView: View {
    @Environment(\.modelContext) private var context
    @Bindable var model: RunnerProcessInspectorModel
    let targets: [RunnerProcessTarget]
    @State private var detail: InspectedRunnerProcess?
    @State private var confirmation: InspectedRunnerProcess?
    @State private var showingConfirmation = false
    @State private var terminationRequest: InspectedRunnerProcess?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RunnerProcessInspectorContent(processes: model.visibleProcesses, targets: targets, selectedRunnerID: $model.selectedRunnerID,
                samplingFailed: model.samplingFailed, isTerminating: model.isTerminating,
                inspect: { detail = $0 }, terminate: { confirmation = $0; showingConfirmation = true })
            if model.operationFailed {
                Text("The termination request could not be completed or fully recorded. The process may still be running. Refresh and check the audit log.", bundle: .module)
                    .foregroundStyle(OctoTheme.warningOrange)
            } else if model.signalSent {
                Text("SIGTERM sent. The process may still be running or may be restarted by its service. Refresh to check.", bundle: .module)
                    .foregroundStyle(OctoTheme.secondaryText)
            }
        }
        .onChange(of: targets.map(\.id)) {
            if let selected = model.selectedRunnerID, !targets.contains(where: { $0.id == selected }) {
                model.selectedRunnerID = nil
            }
        }
        .sheet(item: $detail) { process in RunnerProcessDetailView(process: process) }
        .alert(Text("Request process termination?", bundle: .module), isPresented: $showingConfirmation, presenting: confirmation) { process in
            Button(role: .destructive) { terminationRequest = process } label: { Text("Send SIGTERM", bundle: .module) }
                .accessibilityLabel(Text("Send SIGTERM", bundle: .module))
                .accessibilityHint(Text("Recheck process identity and request termination. Active jobs may fail.", bundle: .module))
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
                .accessibilityLabel(Text("Cancel", bundle: .module))
                .accessibilityHint(Text("Keep the process running.", bundle: .module))
        } message: { process in
            Text("Terminate \(process.name) (PID \(process.id.pid)) for \(process.runner.name)? Active jobs may fail. The service may restart this process. This does not stop the entire runner process tree.", bundle: .module)
        }
        .task(id: terminationRequest?.id) {
            guard !Task.isCancelled, let request = terminationRequest else { return }
            await model.terminate(request, targets: targets, context: context)
            guard !Task.isCancelled else { return }
            terminationRequest = nil
        }
    }
}
