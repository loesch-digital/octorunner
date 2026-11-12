import DesignSystem
import SwiftUI

/// Static guidance only: opening this disclosure never reads runner folders.
struct RunnerWorkspaceHelp: View {
    @State var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                guidance("RUNNER_WORKSPACE", "The pipeline directory inside this runner's _work folder. Use it for build folders outside the checkout, such as DerivedData, SourcePackages and TestResults.")
                guidance("GITHUB_WORKSPACE", "The checkout and default working directory for workflow steps. With the default checkout layout it sits inside RUNNER_WORKSPACE; custom checkout paths can change the layout.")
                guidance("RUNNER_TEMP", "Temporary job files. GitHub cleans this directory at the beginning and end of each job, subject to file permissions.")
                guidance("RUNNER_NAME", "The registered runner name, for example itemflux-1 or itemflux-2. It identifies the runner; it does not configure build paths or simulator isolation.")
                Text("Fastfile example", bundle: .module).font(.headline)
                Text(verbatim: """
                build_root = ENV.fetch("RUNNER_WORKSPACE")
                scan(
                  derived_data_path: File.join(build_root, "DerivedData"),
                  cloned_source_packages_path: File.join(build_root, "SourcePackages"),
                  output_directory: File.join(build_root, "TestResults")
                )
                """)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                Text("Each runner instance has its own _work folder. Later jobs on the same runner can reuse these paths. For separate results per attempt, add GITHUB_RUN_ID and GITHUB_RUN_ATTEMPT to the results path.", bundle: .module)
                Text("Clean only your own build subfolders after all consumers finish. Do not delete _work or RUNNER_WORKSPACE while the job or its post-steps are running. Deleting SourcePackages also removes its cache benefit. Simulators and global Xcode caches require separate configuration.", bundle: .module)
                Text("RUNNER_WORKSPACE is set by the GitHub runner implementation but is currently absent from GitHub's variables reference. This example requires it and stops if it is missing.", bundle: .module)
                Link(destination: URL(string: "https://docs.github.com/en/actions/reference/workflows-and-actions/variables")!) {
                    Text("GitHub Actions variable reference", bundle: .module)
                }
                .accessibilityLabel(Text("GitHub Actions variable reference", bundle: .module))
                .accessibilityHint(Text("Opens the official documentation in your browser", bundle: .module))
            }
            .font(.callout)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 8)
        } label: {
            Text("Workspace variables & build paths", bundle: .module).font(.headline)
        }
        .accessibilityHint(Text("Expand for variable explanations, a selectable Fastfile example and cleanup guidance", bundle: .module))
        .padding(12)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
    }

    private func guidance(_ variable: String, _ explanation: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(verbatim: variable).font(.callout.monospaced().bold()).textSelection(.enabled)
            Text(explanation, bundle: .module)
        }
    }
}
