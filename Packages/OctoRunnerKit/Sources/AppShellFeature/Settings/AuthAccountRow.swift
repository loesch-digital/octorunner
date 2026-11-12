import CoreModels
import DesignSystem
import SwiftUI

struct AuthAccountRow: View {
    let account: GitHubAccountEntity
    let isBusy: Bool
    let activate: () -> Void
    let reauthenticate: () -> Void
    let disconnect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "person.crop.circle")
                    .font(.title2).foregroundStyle(OctoTheme.accentBlue).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: "@\(account.login)").font(.headline).lineLimit(1).help(account.login)
                    if let name = account.displayName, !name.isEmpty {
                        Text(verbatim: name).foregroundStyle(.secondary).lineLimit(1).help(name)
                    }
                    if account.keychainAccountKey.isEmpty {
                        Label { Text("Reauthentication required", bundle: .module) } icon: { Image(systemName: "exclamationmark.triangle") }
                            .foregroundStyle(OctoTheme.warningOrange)
                    } else if account.isActive {
                        Label { Text("Selected account", bundle: .module) } icon: { Image(systemName: "checkmark.circle") }
                            .foregroundStyle(OctoTheme.onlineGreen)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            LabeledContent {
                if account.authMethodRaw == "pat" {
                    Text("Personal access token", bundle: .module)
                } else if account.authMethodRaw == "oauth_device" {
                    Text("GitHub device flow", bundle: .module)
                } else {
                    Text("Unknown authentication method", bundle: .module)
                }
            } label: {
                Text("Authentication method", bundle: .module)
            }
            LabeledContent {
                Text(account.connectedAt, format: .dateTime.year().month().day().hour().minute())
            } label: {
                Text("Last authenticated", bundle: .module)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Last reported OAuth scopes", bundle: .module).font(.subheadline.weight(.semibold))
                if account.scopes.isEmpty {
                    Text("GitHub did not report OAuth scopes. Fine-grained token permissions are checked by each API operation.", bundle: .module)
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                } else {
                    let scopes = Array(Set(account.scopes)).sorted().joined(separator: ", ")
                    Text(verbatim: scopes).font(.caption.monospaced()).lineLimit(3).help(scopes).textSelection(.enabled)
                }
            }
            ViewThatFits(in: .horizontal) {
                HStack { accountActions }
                VStack(alignment: .leading) { accountActions }
            }
            .disabled(isBusy)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder private var accountActions: some View {
        if !account.isActive && !account.keychainAccountKey.isEmpty {
            Button(action: activate) { Text("Use account", bundle: .module) }
                .accessibilityLabel(Text("Use account", bundle: .module))
                .accessibilityValue(Text(verbatim: account.login))
                .accessibilityHint(Text("Selects this account for GitHub API requests without stopping runners.", bundle: .module))
        }
        Button(action: reauthenticate) { Text("Re-authenticate", bundle: .module) }
            .accessibilityLabel(Text("Re-authenticate", bundle: .module))
            .accessibilityValue(Text(verbatim: account.login))
            .accessibilityHint(Text("Sign in with the same GitHub identity to replace its credentials.", bundle: .module))
        Button(role: .destructive, action: disconnect) { Text("Disconnect account…", bundle: .module) }
            .accessibilityLabel(Text("Disconnect account…", bundle: .module))
            .accessibilityValue(Text(verbatim: account.login))
            .accessibilityHint(Text("Asks before removing this account and its local credentials. Runner services keep running.", bundle: .module))
    }
}
