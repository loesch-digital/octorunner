import CoreModels
import DesignSystem
import GitHubAPI
import SwiftData
import SwiftUI
import SyncKit

struct RunnerAccessSettingsCard: View {
    let account: GitHubAccountEntity?
    @Environment(\.locale) private var locale
    @Query private var runners: [RunnerEntity]
    @State private var review = RunnerAccessReview()
    @State private var task: Task<Void, Never>?
    @State private var isChecking = false
    @State private var couldNotReadToken = false

    private let credentials = GitHubRunnerProvisioningClient()
    private var selection: RunnerSyncAccount? { account.map(RunnerSyncAccount.init) }

    private var localRegistrations: [URL: Set<RunnerAccessReview.LocalRegistration>] {
        runners.reduce(into: [:]) { scopes, runner in
            guard let url = URL(string: runner.scopeUrlString),
                  let scope = try? GitHubRunnerProvisioningClient.parseOwnerAndRepo(from: url) else { return }
            let path = [scope.owner, scope.repo].compactMap { $0?.lowercased() }.joined(separator: "/")
            guard let key = URL(string: "https://github.com/\(path)") else { return }
            if let id = runner.githubRunnerId {
                scopes[key, default: []].insert(.init(id: id, name: runner.name))
            } else if scopes[key] == nil {
                scopes[key] = []
            }
        }
    }

    var body: some View {
        let registrations = localRegistrations
        let scopes = registrations.keys.sorted { $0.absoluteString < $1.absoluteString }
        let selection = selection
        SettingsCard("Runner access", symbol: "lock.rectangle.stack",
            subtitle: "Check access to GitHub repositories and organizations configured on this Mac.") {
            Button {
                guard let selection else { return }
                task = Task { await refresh(scopes: Set(scopes), selection: selection) }
            } label: {
                Label { Text("Check Runner Permissions", bundle: .module) } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .accessibilityHint(Text("Reads runner and group access using the selected GitHub account.", bundle: .module))
            .disabled(isChecking || selection == nil || scopes.isEmpty)
            if isChecking {
                ProgressView { Text("Checking GitHub runner access…", bundle: .module) }
            }
            if couldNotReadToken {
                Text("Reconnect GitHub to check runner access.", bundle: .module)
                    .foregroundStyle(OctoTheme.warningOrange)
            }
            if scopes.isEmpty {
                Text("Add or import a runner to check access to its GitHub target.", bundle: .module)
                    .foregroundStyle(OctoTheme.secondaryText)
            }
            if let snapshot = review.snapshot, snapshot.account == selection, !isChecking {
                ForEach(scopes, id: \.self) { scope in
                    if let check = snapshot.checks[scope] {
                        accessRow(scope: scope, check: check, registrations: registrations[scope, default: []])
                    }
                }
                Text("Last checked \(snapshot.checkedAt.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale)))", bundle: .module)
                    .font(.caption)
                    .foregroundStyle(OctoTheme.secondaryText)
            }
        }
        .onChange(of: selection) {
            task?.cancel()
            isChecking = false
            couldNotReadToken = false
        }
        .onDisappear {
            task?.cancel()
            isChecking = false
        }
    }

    private func accessRow(scope: URL, check: RunnerAccessReview.Check,
                           registrations: Set<RunnerAccessReview.LocalRegistration>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(scope.path().trimmingCharacters(in: CharacterSet(charactersIn: "/"))).font(.headline)
            if let count = check.runnerCount {
                Text("Registered runners on GitHub: \(count)", bundle: .module)
                if let localCount = check.matchingRunnerCount(registrations) {
                    Text("Verified runners from this Mac: \(localCount)", bundle: .module)
                }
            } else {
                Text(accessMessage(check.runners), bundle: .module)
                    .foregroundStyle(OctoTheme.warningOrange)
            }
            if let groups = check.groups {
                if case .available(let values, _, _) = groups {
                    Text("Runner groups reported by GitHub: \(values.map(\.name).sorted().joined(separator: ", "))", bundle: .module)
                } else {
                    Text(accessMessage(groups), bundle: .module)
                        .foregroundStyle(OctoTheme.warningOrange)
                }
            }
        }
        .font(.callout)
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }

    private func accessMessage<Item>(_ result: GitHubRunnerInventory<Item>) -> LocalizedStringKey {
        switch result {
        case .forbidden: "GitHub denied access to this list."
        case .unauthorized: "Reconnect GitHub to check runner access."
        case .rateLimited: "GitHub rate limit reached. Try again later."
        case .unavailable, .available: "GitHub could not verify access to this list."
        }
    }

    private func refresh(scopes: Set<URL>, selection: RunnerSyncAccount) async {
        guard !isChecking, !Task.isCancelled else { return }
        isChecking = true
        couldNotReadToken = false
        defer { if !Task.isCancelled { isChecking = false } }
        do {
            let token = try await credentials.readToken(for: selection.credentialKey)
            guard !Task.isCancelled, self.selection == selection else { return }
            try await review.refresh(scopes: scopes, account: selection, token: token)
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, self.selection == selection else { return }
            couldNotReadToken = true
        }
    }
}
