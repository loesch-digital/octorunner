import CoreModels
import DesignSystem
import GitHubAPI
import SwiftUI

struct WorkflowJobDetailCard: View {
    @Environment(\.locale) private var locale
    @State private var isExpanded = true
    let job: GitHubWorkflowJobDTO
    let selection: WorkflowRunDetailSelection
    var openLog: (() -> Void)? = nil

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text(job.runnerName ?? "—").font(.caption).textSelection(.enabled)
                if let openLog {
                    Button(action: openLog) { Text("Load job log", bundle: .module) }
                        .accessibilityLabel(Text("Load job log", bundle: .module))
                        .accessibilityHint(Text("Downloads a bounded log snapshot for this job", bundle: .module))
                }
                if let url = jobURL {
                    Link(destination: url) { Text("Open job on GitHub", bundle: .module) }
                        .accessibilityLabel(Text("Open job on GitHub", bundle: .module))
                        .accessibilityHint(Text("Opens this job and its logs in your browser", bundle: .module))
                }
                if let steps = job.steps {
                    if steps.isEmpty { Text("No steps reported", bundle: .module).foregroundStyle(OctoTheme.secondaryText) }
                    ForEach(steps.sorted { $0.number < $1.number }, id: \.number) { step in
                        WorkflowJobStepView(step: step.snapshot)
                    }
                } else {
                    Text("Step details unavailable", bundle: .module).foregroundStyle(OctoTheme.secondaryText)
                }
            }.padding(.top, 8)
        } label: {
            let display = WorkflowStepPresentation(step: .init(number: 0, name: job.name, status: job.status,
                conclusion: job.conclusion, startedAt: job.startedAt, completedAt: job.completedAt), locale: locale)
            VStack(alignment: .leading, spacing: 4) {
                Text(job.name).font(.headline).fixedSize(horizontal: false, vertical: true)
                Label(display.title, systemImage: display.symbol).font(.caption)
            }
        }
        .accessibilityLabel(Text(job.name))
        .accessibilityHint(Text("Shows steps, runner and links for this job", bundle: .module))
        .padding(14).background(OctoTheme.surface, in: .rect(cornerRadius: 10))
    }

    private var jobURL: URL? {
        guard let slug = GitHubRepositorySlug(input: selection.source.repository), job.id > 0, selection.runID > 0 else { return nil }
        return URL(string: "https://github.com/\(slug.rawValue)/actions/runs/\(selection.runID)/job/\(job.id)")
    }
}
