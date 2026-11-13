import CoreModels
import DesignSystem
import SwiftUI

struct RunnerLastJobView: View {
    @Environment(\.locale) private var locale
    let entry: WorkflowHistoryEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Last completed job", bundle: .module)
                .font(.caption).foregroundStyle(OctoTheme.secondaryText)
            if let entry {
                let presentation = WorkflowHistoryPresentation(entry: entry, locale: locale)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { outcome(entry, presentation: presentation); timestamp(entry) }
                    VStack(alignment: .leading, spacing: 4) { outcome(entry, presentation: presentation); timestamp(entry) }
                }
                Text(entry.jobName ?? entry.workflowName)
                    .font(.caption).lineLimit(1).truncationMode(.middle)
                    .help(entry.jobName ?? entry.workflowName)
                if let url = workflowURL(entry) {
                    Link(destination: url) { Text("View job on GitHub", bundle: .module) }
                        .font(.caption)
                        .accessibilityHint(Text("Opens the workflow run and its job logs in your browser", bundle: .module))
                }
            } else {
                Text("No completed job loaded", bundle: .module)
                    .font(.caption).foregroundStyle(OctoTheme.secondaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("RunnerLastCompletedJob")
    }

    private func outcome(_ entry: WorkflowHistoryEntry, presentation: WorkflowHistoryPresentation) -> some View {
        Label(presentation.status, systemImage: presentation.symbol)
            .font(.caption.bold())
            .foregroundStyle(LocalJobResults.isFailure(entry) ? OctoTheme.errorRed : entry.conclusion == "success" ? OctoTheme.onlineGreen : OctoTheme.secondaryText)
    }

    @ViewBuilder private func timestamp(_ entry: WorkflowHistoryEntry) -> some View {
        if let date = entry.completedAt {
            Text(date, format: .dateTime.day().month().hour().minute().second())
                .font(.caption.monospaced()).foregroundStyle(OctoTheme.secondaryText)
        }
    }

    private func workflowURL(_ entry: WorkflowHistoryEntry) -> URL? {
        guard let slug = GitHubRepositorySlug(input: entry.repository), entry.githubRunID > 0,
              let attempt = entry.attempt, attempt > 0 else { return nil }
        return URL(string: "https://github.com/\(slug.rawValue)/actions/runs/\(entry.githubRunID)/attempts/\(attempt)")
    }
}
