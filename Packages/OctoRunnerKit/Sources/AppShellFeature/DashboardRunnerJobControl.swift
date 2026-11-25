import CoreModels
import DesignSystem
import SwiftUI

struct DashboardRunnerJobControl: View {
    let results: LocalJobResults
    let runnerID: UUID
    let isRunning: Bool
    let observationMaxAge: TimeInterval
    let openJobs: (WorkflowHistoryEntry?) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 15)) { timeline in
            if isRunning {
                let job = results.runningJob(for: runnerID, at: timeline.date, maxAge: observationMaxAge)
                Button { openJobs(job.flatMap(results.workflow(for:))) } label: {
                    if let job {
                        let names = [job.workflowName, job.jobName ?? ""].filter { !$0.isEmpty }
                        Label(names.isEmpty ? "#\(job.githubRunID)" : names.joined(separator: " · "), systemImage: "play.circle")
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Label { Text("Show running workflows", bundle: .module) } icon: { Image(systemName: "play.circle") }
                    }
                }
                .tint(OctoTheme.accentBlue)
                .accessibilityHint(Text("Opens Jobs & Workflow Runs and shows the current run when available.", bundle: .module))
            }
        }
    }
}
