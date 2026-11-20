import CoreModels
import DesignSystem
import Foundation
import SwiftUI
import SyncKit

public struct RunnerSyncObservation: Sendable {
    let comparison: RunnerReconciliation
    let localStatus: RunnerStatus
    let localObservedAt: Date
    let remoteObservedAt: Date

    @MainActor
    init?(runner: RunnerEntity, account: GitHubAccountEntity, snapshot: RunnerSyncSnapshot) {
        guard account.isActive, snapshot.account == RunnerSyncAccount(account),
              let config = LocalDotRunnerConfig(runner), snapshot.configurations[runner.id] == config,
              let result = snapshot.results[runner.id] else { return nil }
        self.init(comparison: RunnerReconciler.compare(
            expectedID: config.agentId, expectedName: runner.name, localStatus: runner.status,
            localLabels: runner.labels, result: result
        ), localStatus: runner.status, localObservedAt: runner.lastHeartbeat, remoteObservedAt: snapshot.observedAt)
    }

    init(comparison: RunnerReconciliation, localStatus: RunnerStatus, localObservedAt: Date, remoteObservedAt: Date) {
        self.comparison = comparison
        self.localStatus = localStatus
        self.localObservedAt = localObservedAt
        self.remoteObservedAt = remoteObservedAt
    }
}

#Preview("Runner sync conflict") {
    RunnerSyncStatusView(observation: RunnerSyncObservation(
        comparison: RunnerReconciler.compare(
            expectedID: 1, expectedName: "mac-runner", localStatus: .idle,
            localLabels: ["self-hosted"], result: .notFound
        ),
        localStatus: .idle, localObservedAt: .now, remoteObservedAt: .now
    ), showsDetails: true)
    .padding()
    .frame(width: 300)
    .background(OctoTheme.surfaceLowest)
}

struct RunnerSyncStatusView: View {
    @Environment(\.locale) private var locale
    let observation: RunnerSyncObservation
    var showsDetails = false

    private var comparison: RunnerReconciliation { observation.comparison }
    private var needsAttention: Bool {
        switch comparison.presence {
        case .reported: comparison.hasStatusConflict || comparison.hasLabelConflict
        default: true
        }
    }

    private var text: String {
        switch comparison.presence {
        case .reported(let status):
            AppLocalization.string("GitHub reports \(status.localizedBadgeTitle(locale: locale))", locale: locale)
        case .differentRegistration:
            AppLocalization.string("GitHub registration differs", locale: locale)
        case .notFound:
            AppLocalization.string("GitHub cannot confirm this runner", locale: locale)
        case .missingFromScope:
            AppLocalization.string("Runner missing from the GitHub scope", locale: locale)
        case .unauthorized:
            AppLocalization.string("Reconnect GitHub to check this runner", locale: locale)
        case .forbidden:
            AppLocalization.string("GitHub runner access is restricted", locale: locale)
        case .rateLimited(let retryAt):
            AppLocalization.string("GitHub limit reached. Next check after \(formatted(retryAt)).", locale: locale)
        case .unavailable:
            AppLocalization.string("GitHub runner status is unavailable", locale: locale)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(text, systemImage: needsAttention ? "exclamationmark.circle" : "network")
                .foregroundStyle(needsAttention ? OctoTheme.warningOrange : OctoTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            if comparison.hasStatusConflict {
                Text("The local and GitHub statuses differ.", bundle: .module)
            }
            if comparison.hasLabelConflict {
                Text("Local labels differ from GitHub.", bundle: .module)
            }
            if showsDetails {
                Text("Local process \(observation.localStatus.localizedBadgeTitle(locale: locale)) · \(formatted(observation.localObservedAt))", bundle: .module)
                Text("GitHub sync started \(formatted(observation.remoteObservedAt))", bundle: .module)
                if comparison.presence == .notFound {
                    Text("The runner may have been removed or the selected account may lack access.", bundle: .module)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(OctoTheme.secondaryText)
        .textSelection(.enabled)
        .accessibilityElement(children: .combine)
    }

    private func formatted(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }
}
