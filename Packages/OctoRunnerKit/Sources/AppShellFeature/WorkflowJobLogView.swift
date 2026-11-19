import DesignSystem
import SwiftUI

struct WorkflowJobLogView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let selection: WorkflowJobLogSelection
    @State private var model: WorkflowJobLogModel
    @State private var request: UUID?

    init(selection: WorkflowJobLogSelection, model: WorkflowJobLogModel? = nil,
         rateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget()) {
        self.selection = selection
        _model = State(initialValue: model ?? WorkflowJobLogModel(rateBudget: rateBudget))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selection.jobName).font(.title2.bold()).lineLimit(2).help(selection.jobName)
                    Text(selection.detail.source.repository).font(.caption).textSelection(.enabled)
                    Text("Run #\(selection.detail.runID) · Attempt \(selection.detail.attempt)", bundle: .module).font(.caption)
                }
                Spacer()
                Button { dismiss() } label: { Text("Close", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Close job log", bundle: .module))
                    .accessibilityHint(Text("Returns to workflow details", bundle: .module))
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            Text("Logs load only on request. This is a snapshot, not a live stream.", bundle: .module)
                .font(.caption).foregroundStyle(OctoTheme.secondaryText)
            if model.isLoading { ProgressView { Text("Loading job log…", bundle: .module) } }
            if let error = model.error {
                Text(AppLocalization.string(errorText(error), locale: locale)).foregroundStyle(OctoTheme.errorRed)
            }
            if let snapshot = model.snapshot {
                HStack {
                    Text("Observed", bundle: .module)
                    Text(snapshot.observedAt, format: .dateTime.hour().minute().second())
                }.font(.caption).foregroundStyle(OctoTheme.secondaryText)
                if snapshot.isTruncated {
                    Label { Text("Log truncated to 1 MiB. Open GitHub for the complete output.", bundle: .module) }
                        icon: { Image(systemName: "exclamationmark.triangle") }
                        .font(.caption).foregroundStyle(OctoTheme.warningOrange)
                }
                ScrollView([.horizontal, .vertical]) {
                    Text(snapshot.text.isEmpty ? AppLocalization.string("The log contains no output", locale: locale) : snapshot.text)
                        .font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .topLeading).padding(12)
                        .accessibilityLabel(Text("Job log output", bundle: .module))
                }.background(OctoTheme.surface, in: .rect(cornerRadius: 8))
            } else { Spacer(minLength: 0) }
        }
        .padding(20).frame(minWidth: 520, minHeight: 420).background(OctoTheme.surfaceLowest)
        .task(id: request) {
            model.select(selection)
            guard request != nil, !Task.isCancelled else { return }
            await model.loadJobLog(selection: selection)
        }
        .onDisappear { model.invalidate() }
    }

    @ViewBuilder private var actions: some View {
        Button { request = UUID() } label: {
            Label { Text("Load job log", bundle: .module) } icon: { Image(systemName: "doc.text") }
        }
        .disabled(model.isLoading)
        .accessibilityLabel(Text("Load job log", bundle: .module))
        .accessibilityHint(Text("Downloads a bounded log snapshot for this job", bundle: .module))
        if let url = selection.webURL {
            Link(destination: url) { Text("Open job on GitHub", bundle: .module) }
                .accessibilityLabel(Text("Open job on GitHub", bundle: .module))
                .accessibilityHint(Text("Opens this job and its logs in your browser", bundle: .module))
        }
    }

    private func errorText(_ error: WorkflowJobLogLoadError) -> String.LocalizationValue {
        switch error {
        case .authenticationRequired: "Reconnect this GitHub account to load history"
        case .permissionDenied: "This token cannot read Actions for the selected repository"
        case .notAvailable: "Logs are not available yet or have expired. Open GitHub for the current job."
        case .rateLimited: "GitHub rate limit reached; refresh is paused"
        case .unsupportedContent: "This log is not supported UTF-8 text. Open it on GitHub."
        case .unavailable: "Job log could not be loaded. Open GitHub or try again."
        }
    }
}
