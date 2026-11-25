import CoreModels
import DesignSystem
import GitHubAPI
import SwiftUI

struct WorkflowRunDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    let entry: WorkflowHistoryEntry
    let selection: WorkflowRunDetailSelection
    @State private var model: WorkflowRunDetailModel
    @State private var refreshTicket = UUID()
    @State private var selectedLog: WorkflowJobLogSelection?
    private let rateBudget: WorkflowHistoryRateBudget

    init(entry: WorkflowHistoryEntry, selection: WorkflowRunDetailSelection,
         rateBudget: WorkflowHistoryRateBudget = WorkflowHistoryRateBudget(), model: WorkflowRunDetailModel? = nil) {
        self.entry = entry; self.selection = selection
        self.rateBudget = rateBudget
        _model = State(initialValue: model ?? WorkflowRunDetailModel(rateBudget: rateBudget))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(entry.workflowName.isEmpty ? "#\(entry.githubRunID)" : entry.workflowName)
                        .font(.title2.bold()).lineLimit(2).help(entry.workflowName)
                    Text(entry.repository).font(.subheadline).textSelection(.enabled)
                    HStack {
                        Text(entry.branch).lineLimit(1).truncationMode(.middle).help(entry.branch)
                        Text(String(entry.commitSHA.prefix(7))).help(entry.commitSHA)
                    }.font(.caption.monospaced()).foregroundStyle(OctoTheme.secondaryText)
                    Text("Run #\(String(selection.runID)) · Attempt \(selection.attempt)", bundle: .module).font(.caption)
                }
                Spacer(minLength: 8)
                Button { dismiss() } label: { Text("Close", bundle: .module) }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel(Text("Close workflow details", bundle: .module))
                    .accessibilityHint(Text("Returns to workflow history", bundle: .module))
            }
            ViewThatFits(in: .horizontal) {
                HStack { actions }
                VStack(alignment: .leading, spacing: 8) { actions }
            }
            WorkflowPullRequestLinksView(entry: entry)
            if let workflow = model.workflow {
                let status = WorkflowStepPresentation(step: .init(number: 0, name: workflow.name ?? "",
                    status: workflow.status ?? "unknown", conclusion: workflow.conclusion, startedAt: nil, completedAt: nil), locale: locale)
                HStack(spacing: 12) {
                    Label(status.title, systemImage: status.symbol).foregroundStyle(status.color)
                    Text("Duration", bundle: .module)
                    TimelineView(.periodic(from: .now, by: model.shouldRefresh ? 1 : 15)) { timeline in
                        Text(WorkflowHistoryPresentation.duration(workflowDuration(workflow, at: timeline.date)))
                            .monospacedDigit()
                    }
                }
                .font(.subheadline)
            }
            if let observed = model.observedAt {
                HStack {
                    Text("Observed", bundle: .module)
                    Text(observed, format: .dateTime.hour().minute().second())
                }.font(.caption).foregroundStyle(OctoTheme.secondaryText)
            }
            if model.isLoading { ProgressView { Text("Loading job details…", bundle: .module) }.controlSize(.small) }
            if let error = model.error {
                Text(AppLocalization.string(errorText(error), locale: locale)).foregroundStyle(OctoTheme.errorRed)
                    .accessibilityAddTraits(.updatesFrequently)
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    if model.jobs.isEmpty && !model.isLoading && model.error == nil {
                        Text("No job details loaded", bundle: .module).foregroundStyle(OctoTheme.secondaryText)
                    }
                    TimelineView(.periodic(from: .now, by: model.shouldRefresh ? 1 : 15)) { timeline in
                        let now = model.observedAt
                            .map { (-5...90).contains(timeline.date.timeIntervalSince($0)) } == true ? timeline.date : nil
                        ForEach(model.jobs) { job in
                            WorkflowJobDetailCard(job: job, selection: selection, now: now) {
                                selectedLog = .init(detail: selection, jobID: job.id, jobName: job.name)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20).frame(minWidth: 540, minHeight: 420)
        .background(OctoTheme.surfaceLowest)
        .task(id: WorkflowRunDetailRequest(selection: selection, refreshTicket: refreshTicket)) {
            model.select(selection)
            await model.load()
            while !Task.isCancelled, model.error == nil, model.shouldRefresh {
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard !Task.isCancelled else { return }
                await model.load()
            }
        }
        .onDisappear { model.invalidate() }
        .sheet(item: $selectedLog) { log in
            WorkflowJobLogView(selection: log, rateBudget: rateBudget)
        }
    }

    private func workflowDuration(_ workflow: GitHubWorkflowRunDTO, at now: Date) -> Double? {
        if workflow.status == "in_progress",
           let observed = model.observedAt, (-5...90).contains(now.timeIntervalSince(observed)) {
            return WorkflowExecutionDuration.elapsedSeconds(since: workflow.startedAt, at: now)
        }
        if workflow.status == "completed", !model.jobs.isEmpty,
           model.jobs.allSatisfy({ $0.status == "completed" && $0.completedAt != nil }),
           let end = model.jobs.compactMap(\.completedAt).max() {
            return WorkflowExecutionDuration.elapsedSeconds(since: workflow.startedAt, at: end)
        }
        return entry.durationSeconds
    }

    @ViewBuilder private var actions: some View {
        Button { refreshTicket = UUID() } label: {
            Label { Text("Refresh", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
        }
        .disabled(model.isLoading)
        .accessibilityLabel(Text("Refresh job details", bundle: .module))
        .accessibilityHint(Text("Loads jobs and steps for this exact run attempt", bundle: .module))
        if let url = runURL {
            Link(destination: url) { Text("Open workflow on GitHub", bundle: .module) }
                .accessibilityLabel(Text("Open workflow on GitHub", bundle: .module))
                .accessibilityHint(Text("Opens this workflow run and its logs in your browser", bundle: .module))
        }
    }

    private var runURL: URL? {
        guard let slug = GitHubRepositorySlug(input: selection.source.repository), selection.runID > 0, selection.attempt > 0 else { return nil }
        return URL(string: "https://github.com/\(slug.rawValue)/actions/runs/\(selection.runID)/attempts/\(selection.attempt)")
    }

    private func errorText(_ error: WorkflowHistoryLoadError) -> String.LocalizationValue {
        switch error {
        case .authenticationRequired: "Reconnect this GitHub account to load history"
        case .permissionDenied: "This token cannot read Actions for the selected repository"
        case .rateLimited: "GitHub rate limit reached; refresh is paused"
        case .resourceNotFound: "GitHub could not find this Actions resource or it is not visible to this account (HTTP 404)."
        case .tooManyPages: "Job details exceeded the safe pagination limit"
        case .unavailable: "Job details could not be loaded. Open GitHub or try again."
        }
    }
}
