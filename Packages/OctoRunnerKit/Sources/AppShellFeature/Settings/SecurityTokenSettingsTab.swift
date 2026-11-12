import CoreModels
import DesignSystem
import SwiftData
import SwiftUI

public struct SecurityTokenSettingsTab: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.locale) private var locale
    @Query(sort: \GitHubAccountEntity.connectedAt, order: .reverse) private var accounts: [GitHubAccountEntity]
    @State private var accountSession: AccountSessionController
    @State private var showingAuthentication = false
    @State private var showingDisconnect = false
    @State private var disconnectRequest: AccountDisconnectRequest?
    @State private var actionError: String?
    @State private var disconnectTask: Task<Void, Never>?

    public init(accountSession: AccountSessionController = AccountSessionController()) {
        _accountSession = State(initialValue: accountSession)
    }

    public var body: some View {
        Form {
            Section {
                Button { showingAuthentication = true } label: {
                    Label { Text("Connect GitHub account…", bundle: .module) } icon: { Image(systemName: "person.badge.plus") }
                }
                .disabled(accountSession.isBusy)
                .accessibilityLabel(Text("Connect GitHub account…", bundle: .module))
                .accessibilityHint(Text("Opens GitHub device login or personal access token validation.", bundle: .module))
                if accounts.isEmpty {
                    Text("No GitHub accounts connected. Connect an account to manage runners and load workflow history.", bundle: .module)
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if accountSession.isBusy {
                    ProgressView { Text("Removing local credentials…", bundle: .module) }
                        .accessibilityLabel(Text("Removing local credentials…", bundle: .module))
                }
                if let error = actionError ?? accountSession.error?.localizedMessage(locale: locale) {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(OctoTheme.errorRed).fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Connected GitHub accounts", bundle: .module)
            } footer: {
                Text("The selected account is used for GitHub requests. Its token is checked when used; selection alone does not confirm current permissions.", bundle: .module)
            }

            ForEach(orderedAccounts) { account in
                Section {
                    AuthAccountRow(account: account, isBusy: accountSession.isBusy,
                        activate: { activate(account.id) },
                        reauthenticate: { showingAuthentication = true },
                        disconnect: {
                            disconnectRequest = AccountDisconnectRequest(id: account.id, login: account.login)
                            showingDisconnect = true
                        })
                }
            }

            Section {
                Label { Text("Credentials are stored only in macOS Keychain.", bundle: .module) } icon: { Image(systemName: "lock.shield") }
                Text("Sign in with the same GitHub identity to replace credentials. A different identity is added as a separate account.", bundle: .module)
                Text("Token contents and expiration dates are not exposed here. Fine-grained PAT permissions depend on the resources you selected on GitHub.", bundle: .module)
            } header: {
                Text("Credential security", bundle: .module)
            } footer: {
                Text("Disconnect removes local credentials only. Revoke a token or OAuth authorization separately in GitHub Settings. Installed runner services keep running.", bundle: .module)
            }
            .font(.caption)
        }
        .formStyle(.grouped)
        .scrollBounceBehavior(.basedOnSize)
        .background(OctoTheme.surface)
        .accessibilityIdentifier("auth-settings")
        .sheet(isPresented: $showingAuthentication) { OAuthDeviceFlowSheet() }
        .confirmationDialog(Text("Disconnect GitHub account?", bundle: .module), isPresented: $showingDisconnect,
            titleVisibility: .visible, presenting: disconnectRequest) { request in
            Button(role: .destructive) { disconnect(request.id) } label: { Text("Remove local credentials", bundle: .module) }
                .accessibilityLabel(Text("Remove local credentials", bundle: .module))
                .accessibilityHint(Text("Removes the confirmed account and its local credentials. It does not revoke access on GitHub.", bundle: .module))
            Button(role: .cancel) {} label: { Text("Cancel", bundle: .module) }
        } message: { request in
            Text("Local credentials for @\(request.login) will be removed. Runner services keep running; GitHub authorization is not revoked.", bundle: .module)
        }
        .onDisappear { disconnectTask?.cancel() }
    }

    private var orderedAccounts: [GitHubAccountEntity] {
        accounts.filter(\.isActive) + accounts.filter { !$0.isActive }
    }

    private func activate(_ id: UUID) {
        guard !accountSession.isBusy else { return }
        actionError = nil
        do {
            try GitHubAccountStore.activate(accountID: id, in: modelContext)
        } catch GitHubAccountStoreError.reauthenticationRequired {
            actionError = AppLocalization.string("Reauthentication required", locale: locale)
        } catch {
            actionError = AccountSessionError.metadataPersistenceFailed.localizedMessage(locale: locale)
        }
    }

    private func disconnect(_ id: UUID) {
        guard !accountSession.isBusy else { return }
        actionError = nil
        disconnectTask = Task { await accountSession.disconnect(accountID: id, in: modelContext) }
    }
}
