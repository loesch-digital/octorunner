import DesignSystem
import GitHubAPI
import SwiftUI

struct DashboardUpdateBanner: View {
    @Environment(\.locale) private var locale

    let update: AppUpdateInfo
    let isInstallingUpdate: Bool
    let install: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.down.app.fill")
                .font(.system(size: 22))
                .foregroundStyle(OctoTheme.accentBlue)

            VStack(alignment: .leading, spacing: 2) {
                Text(AppLocalization.string("Update Available: OctoRunner v\(update.latestVersion)", locale: locale))
                    .font(.system(size: 13, weight: .bold))
                Text(AppLocalization.string("You are running v\(update.currentVersion). Click 'Install & Relaunch' to update automatically.", locale: locale))
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                install()
            } label: {
                HStack(spacing: 6) {
                    if isInstallingUpdate {
                        ProgressView().controlSize(.small)
                        Text(AppLocalization.string("Updating…", locale: locale))
                    } else {
                        Image(systemName: "bolt.fill")
                        Text(AppLocalization.string("Install & Relaunch", locale: locale))
                    }
                }
                .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .disabled(isInstallingUpdate)
        }
        .padding(14)
        .background(OctoTheme.surfaceHigh, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.accentBlue.opacity(0.6), lineWidth: 1)
        }
    }
}
