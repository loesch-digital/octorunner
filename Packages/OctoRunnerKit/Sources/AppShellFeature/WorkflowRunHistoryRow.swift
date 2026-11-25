import CoreModels
import DesignSystem
import SwiftUI

struct WorkflowRunHistoryRow: View {
    @Environment(\.locale) private var locale
    let entry: WorkflowHistoryEntry
    let jobs: [WorkflowHistoryEntry]
    let now: Date
    let observationMaxAge: TimeInterval
    var openDetails: (() -> Void)? = nil

    var body: some View {
        let presentation = WorkflowHistoryPresentation(entry: entry, now: now, locale: locale, observationMaxAge: observationMaxAge)
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(entry.workflowName.isEmpty ? "#\(entry.githubRunID)" : entry.workflowName)
                        .font(.headline).lineLimit(1).truncationMode(.middle).help(entry.workflowName)
                    Label(presentation.status, systemImage: presentation.symbol)
                        .font(.caption).foregroundStyle(statusColor(presentation.symbol))
                }
                Spacer(minLength: 8)
                if let url = presentation.githubURL {
                    Link(destination: url) {
                        Label { Text("Open on GitHub", bundle: .module) } icon: { Image(systemName: "arrow.up.right.square") }
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel(Text("Open on GitHub", bundle: .module))
                    .accessibilityHint(Text("Opens this workflow run and its logs in your browser", bundle: .module))
                }
            }
            Text(entry.repository).font(.subheadline).lineLimit(1).truncationMode(.middle).help(entry.repository)
            HStack {
                Text(entry.branch).lineLimit(1).truncationMode(.middle).help(entry.branch)
                Spacer(minLength: 8)
                Text(String(entry.commitSHA.prefix(7))).help(entry.commitSHA)
                Text("#\(String(entry.githubRunID))")
            }.font(.caption.monospaced()).foregroundStyle(.secondary)
            HStack {
                Text("Duration", bundle: .module)
                elapsedDuration(entry)
                Spacer()
                if let event = entry.event { Text(event).lineLimit(1).help(event) }
            }.font(.caption)
            if let openDetails {
                Button(action: openDetails) { Text("View workflow details", bundle: .module) }
                    .disabled(entry.attempt == nil)
                    .accessibilityLabel(Text("View workflow details", bundle: .module))
                    .accessibilityHint(Text("Shows jobs and steps for this run attempt", bundle: .module))
            }
            WorkflowPullRequestLinksView(entry: entry)
            if let observed = entry.observedAt {
                HStack {
                    Text("Observed", bundle: .module)
                    Text(observed, format: .dateTime.hour().minute().second())
                }.font(.caption).foregroundStyle(.secondary)
            }
            DisclosureGroup {
                if jobs.isEmpty {
                    Text("No job details loaded", bundle: .module).font(.caption).foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(jobs) { job in
                            let display = WorkflowHistoryPresentation(entry: job, now: now, locale: locale, observationMaxAge: observationMaxAge)
                            VStack(alignment: .leading, spacing: 3) {
                                Label(job.jobName ?? "—", systemImage: display.symbol)
                                    .lineLimit(1).truncationMode(.middle).help(job.jobName ?? "—")
                                HStack {
                                    Text(display.status)
                                    Text(job.runnerName ?? "—").lineLimit(1).truncationMode(.middle).help(job.runnerName ?? "—")
                                    Spacer()
                                    elapsedDuration(job)
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.top, 6)
                }
            } label: { Text("Jobs", bundle: .module).font(.subheadline) }
            .accessibilityLabel(Text("Jobs", bundle: .module))
            .accessibilityHint(Text("Shows job status, assigned runner and measured duration", bundle: .module))
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
    }

    @ViewBuilder private func elapsedDuration(_ entry: WorkflowHistoryEntry) -> some View {
        if entry.status == "in_progress" && entry.isFresh(at: now, maxAge: observationMaxAge) {
            TimelineView(.periodic(from: .now, by: 1)) { timeline in
                Text(WorkflowHistoryPresentation.duration(entry.elapsedDuration(at: timeline.date, maxAge: observationMaxAge)))
            }
        } else {
            Text(WorkflowHistoryPresentation.duration(entry.elapsedDuration(at: now, maxAge: observationMaxAge)))
        }
    }

    private func statusColor(_ symbol: String) -> Color {
        switch symbol {
        case "checkmark.circle.fill": OctoTheme.onlineGreen
        case "xmark.circle.fill": OctoTheme.errorRed
        case "play.circle.fill": OctoTheme.accentBlue
        case "clock": OctoTheme.warningOrange
        default: .secondary
        }
    }
}
