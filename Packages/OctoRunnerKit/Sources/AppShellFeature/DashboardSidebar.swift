import CoreModels
import DesignSystem
import GitHubAPI
import SwiftUI

struct DashboardSidebar: View {
    @Environment(\.locale) private var locale
    @State private var isShowingAccountPopover = false

    @Binding var selectedSection: SidebarSection?
    let usesDashboardSampleData: Bool
    let registeredRunnerCount: Int
    let activeRunnerCount: Int
    let faultedRunnerCount: Int
    let jobResults: LocalJobResults
    let historyObservationMaxAge: TimeInterval
    let historyRepositories: Set<String>
    let engineIndicatorColor: Color
    let account: GitHubAccountEntity?
    let accountIsBusy: Bool
    let showAuthentication: () -> Void
    let syncRunners: () -> Void
    let checkForUpdates: () -> Void
    let signOut: (GitHubAccountEntity) -> Void

    var body: some View {
        VStack(spacing: 0) {
            List(selection: usesDashboardSampleData ? .constant(nil) : $selectedSection) {
                Section(AppLocalization.string("RUNNER STATUS", locale: locale)) {
                    ForEach(SidebarSection.allCases) { section in
                        HStack {
                            if section == .queueWorkpools {
                                Label { Text("Jobs & Workflow Runs", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else if section == .launchdSettings {
                                Label { Text("App Settings", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else if section == .hostTelemetry {
                                Label { Text("Host Telemetry", bundle: .module) } icon: { Image(systemName: section.systemImage) }
                            } else {
                                Label(AppLocalization.string(String.LocalizationValue(stringLiteral: section == .allRunners ? "All runners" : section.title), locale: locale), systemImage: section.systemImage)
                            }
                            Spacer()
                            if section == .queueWorkpools {
                                TimelineView(.periodic(from: .now, by: 15)) { timeline in
                                    let active = jobResults.runningWorkflowCount(at: timeline.date, maxAge: historyObservationMaxAge,
                                        repositories: historyRepositories)
                                    if active > 0 {
                                        Text(active, format: .number)
                                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .accessibilityLabel(Text("Running workflows: \(active)", bundle: .module))
                                    }
                                }
                                .fixedSize()
                            } else if section != .launchdSettings && section != .hostTelemetry {
                              Text("\(runnerCount(for: section))")
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                        .tag(section)
                    }
                }
            }
            .listStyle(.sidebar)

            Divider()

            sidebarBottomAccountCard

            Divider()

            sidebarVersionFooter
        }
    }

    private var sidebarBottomAccountCard: some View {
        Group {
            if let account {
                connectedAccount(account)
            } else {
                signInButton
            }
        }
        .background(OctoTheme.surfaceLow)
    }

    private var sidebarVersionFooter: some View {
        HStack {
            Text(usesDashboardSampleData ? "OctoRunner" : "OctoRunner v\(AppUpdaterActor.currentBundleVersion)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Circle()
                .fill(engineIndicatorColor)
                .frame(width: 6, height: 6)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 28, maxHeight: 28)
        .background(OctoTheme.surfaceLow)
    }

    private func connectedAccount(_ activeAccount: GitHubAccountEntity) -> some View {
        Button {
            isShowingAccountPopover.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 26))
                    .foregroundStyle(OctoTheme.accentBlue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(activeAccount.displayName ?? activeAccount.login)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("@\(activeAccount.login)")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OctoTheme.accentBlue)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isShowingAccountPopover, arrowEdge: .trailing) {
            accountPopoverContent(activeAccount)
        }
    }

    private var signInButton: some View {
        Button {
            showAuthentication()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: 24))
                    .foregroundStyle(OctoTheme.accentBlue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppLocalization.string("Sign in with GitHub", locale: locale))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(AppLocalization.string("Connect OAuth or PAT", locale: locale))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private func accountPopoverContent(_ account: GitHubAccountEntity) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            accountIdentity(account)

            Divider()

            Button {
                isShowingAccountPopover = false
                syncRunners()
            } label: {
                Label(AppLocalization.string("Sync Local & GitHub Runners", locale: locale), systemImage: "arrow.triangle.2.circlepath.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isShowingAccountPopover = false
                selectedSection = .launchdSettings
            } label: {
                Label { Text("App Settings", bundle: .module) } icon: { Image(systemName: "gearshape") }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isShowingAccountPopover = false
                checkForUpdates()
            } label: {
                Label(AppLocalization.string("Check for Updates (v\(AppUpdaterActor.currentBundleVersion))", locale: locale), systemImage: "arrow.triangle.2.circlepath")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button {
                isShowingAccountPopover = false
                showAuthentication()
            } label: {
                Label(AppLocalization.string("Switch / Re-authenticate Account…", locale: locale), systemImage: "person.badge.key.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Divider()

            Button(role: .destructive) {
                isShowingAccountPopover = false
                signOut(account)
            } label: {
                Label(AppLocalization.string("Sign Out @\(account.login)", locale: locale), systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(OctoTheme.errorRed)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(accountIsBusy)
        }
        .padding(14)
        .frame(width: 265)
    }

    @ViewBuilder
    private func accountIdentity(_ account: GitHubAccountEntity) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 28))
                .foregroundStyle(OctoTheme.accentBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(account.displayName ?? account.login)
                    .font(.system(size: 13, weight: .bold))
                Text("@\(account.login)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(OctoTheme.accentBlue)
            }
            Spacer()
        }

        Text(AppLocalization.string("Scopes: \(account.scopes.isEmpty ? AppLocalization.string("Not reported by token; permissions checked when used", locale: locale) : account.scopes.joined(separator: ", "))", locale: locale))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
    }

    private func runnerCount(for section: SidebarSection) -> Int {
        switch section {
        case .activeDaemons: activeRunnerCount
        case .failedFaulted: faultedRunnerCount
        default: registeredRunnerCount
        }
    }
}
