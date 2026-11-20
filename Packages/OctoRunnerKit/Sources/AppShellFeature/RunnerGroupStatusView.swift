import DesignSystem
import GitHubAPI
import SwiftUI
import SyncKit

struct RunnerGroupStatusView: View {
    let configuration: LocalDotRunnerConfig
    let groupID: Int64
    let groupName: String?
    let account: RunnerSyncAccount?
    @State private var membership: RunnerGroupMembership?
    @State private var task: Task<Void, Never>?
    @State private var isChecking = false

    private let sync = GitHubRunnerSyncActor()
    private let credentials = GitHubRunnerProvisioningClient()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let groupName {
                Text("Local runner group: \(groupName)", bundle: .module)
            }
            Button {
                guard let account else { return }
                task = Task { await check(account) }
            } label: {
                Text("Check GitHub Group", bundle: .module)
            }
            .accessibilityHint(Text("Verifies this runner's membership in the configured group.", bundle: .module))
            .disabled(account == nil || isChecking)
            if isChecking {
                ProgressView { Text("Checking GitHub group…", bundle: .module) }
            }
            if let membership {
                switch membership {
                case .member:
                    Text("GitHub confirms membership in this group.", bundle: .module)
                case .different:
                    Text("The runner is missing from the configured GitHub group.", bundle: .module)
                        .foregroundStyle(OctoTheme.warningOrange)
                case .unverified:
                    Text("GitHub could not verify group membership.", bundle: .module)
                        .foregroundStyle(OctoTheme.warningOrange)
                }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
        .onDisappear {
            task?.cancel()
            isChecking = false
        }
        .onChange(of: account) {
            task?.cancel()
            isChecking = false
            membership = nil
        }
    }

    private func check(_ account: RunnerSyncAccount) async {
        guard !isChecking, !Task.isCancelled else { return }
        isChecking = true
        membership = nil
        defer { if !Task.isCancelled { isChecking = false } }
        do {
            let token = try await credentials.readToken(for: account.credentialKey)
            let inventory = try await sync.inventory(for: configuration.gitHubUrl, groupID: groupID, token: token) {
                await GitHubAccountStore.selectionRevision == account.selectionRevision
            }
            guard !Task.isCancelled, GitHubAccountStore.selectionRevision == account.selectionRevision else { return }
            membership = RunnerGroupMembership.resolve(runnerID: configuration.agentId, from: inventory)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, GitHubAccountStore.selectionRevision == account.selectionRevision else { return }
            membership = .unverified
        }
    }
}
