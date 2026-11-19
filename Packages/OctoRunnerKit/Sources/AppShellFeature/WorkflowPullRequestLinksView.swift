import CoreModels
import SwiftUI

struct WorkflowPullRequestLinksView: View {
    let entry: WorkflowHistoryEntry

    var body: some View {
        if let requests = entry.pullRequests, !requests.isEmpty {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { links(requests) }
                VStack(alignment: .leading, spacing: 6) { links(requests) }
            }
        } else if entry.event?.hasPrefix("pull_request") == true {
            Text("Pull request details unavailable", bundle: .module)
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func links(_ requests: [WorkflowPullRequestReference]) -> some View {
        ForEach(requests) { request in
            Link(destination: request.url) {
                Label("PR #\(request.number)", systemImage: "arrow.triangle.pull")
            }
            .font(.caption)
            .accessibilityLabel(Text("Open pull request #\(request.number)", bundle: .module))
            .accessibilityHint(Text("Opens the associated pull request on GitHub", bundle: .module))
            .help(request.url.absoluteString)
        }
    }
}
