import CoreModels
import DesignSystem
import GitHubAPI
import SwiftData
import SwiftUI

public struct OAuthDeviceFlowSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = OAuthDeviceFlowViewModel()

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            sheetHeaderBar
            Divider()
            mainContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            sheetFooterBar
        }
        .frame(width: 580, height: 500)
        .background(OctoTheme.surface)
        .onDisappear {
            viewModel.cancelFlow()
        }
    }

    private var sheetHeaderBar: some View {
        HStack {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .foregroundStyle(OctoTheme.accentBlue)
                Text("OctoRunner — GitHub Authentication")
                    .font(.system(size: 13, weight: .semibold))
            }
            Spacer()
            Button("Close", systemImage: "xmark.circle.fill") {
                viewModel.cancelFlow()
                dismiss()
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(OctoTheme.surfaceHigh)
    }

    @ViewBuilder
    private var mainContentArea: some View {
        switch viewModel.state {
        case .initial, .requestingDeviceCode:
            initialStateView
        case .codeGenerated(let response):
            codeDisplayStateView(response)
        case .polling(let response):
            pollingStateView(response)
        case .authenticated(let session):
            successStateView(session)
        }
    }

    // MARK: - State A: Initial

    private var initialStateView: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "infinity.circle.fill")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 58, height: 58)
                    .foregroundStyle(OctoTheme.accentBlue)
                    .padding(8)
                    .background(OctoTheme.surfaceHighest, in: .rect(cornerRadius: 16))

                HStack(spacing: 4) {
                    Circle()
                        .fill(OctoTheme.onlineGreen)
                        .frame(width: 6, height: 6)
                    Text("READY")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(OctoTheme.surfaceHigh, in: .capsule)
                .offset(x: 8, y: 4)
            }

            VStack(spacing: 4) {
                Text("OctoRunner")
                    .font(.system(size: 21, weight: .bold))
                Text("FOR GITHUB ACTIONS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(OctoTheme.accentBlue)
                Text("Manage your local macOS runners securely with native background persistence.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(OctoTheme.errorRed)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(OctoTheme.errorRed.opacity(0.14), in: .rect(cornerRadius: 6))
            }

            Button {
                Task { await viewModel.startDeviceFlow() }
            } label: {
                HStack(spacing: 8) {
                    if viewModel.state == .requestingDeviceCode {
                        ProgressView()
                            .controlSize(.small)
                        Text("Requesting Device Code...")
                    } else {
                        Image(systemName: "person.badge.key.fill")
                        Text("Sign in with GitHub (OAuth Device Flow)")
                        Image(systemName: "arrow.right")
                    }
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: 440, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
            .disabled(viewModel.state == .requestingDeviceCode)

            HStack {
                Rectangle().fill(OctoTheme.outlineVariant.opacity(0.4)).frame(height: 1)
                Text("OR")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Rectangle().fill(OctoTheme.outlineVariant.opacity(0.4)).frame(height: 1)
            }
            .frame(maxWidth: 440)

            patInputCard
                .frame(maxWidth: 440)

            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(OctoTheme.onlineGreen)
                Text("Requires repo, workflow, and admin:org scopes. Stored securely in macOS Keychain.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
    }

    private var patInputCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Or enter a Personal Access Token (PAT) manually", systemImage: "key.fill")
                    .font(.system(size: 11, weight: .medium))
                Spacer()
                Link("Create Token ↗", destination: URL(string: "https://github.com/settings/tokens")!)
                    .font(.system(size: 10, design: .monospaced))
            }

            HStack(spacing: 8) {
                Group {
                    if viewModel.isPATVisible {
                        TextField("ghp_••••••••••••••••••••••••••••••••", text: $viewModel.patInput)
                    } else {
                        SecureField("ghp_••••••••••••••••••••••••••••••••", text: $viewModel.patInput)
                    }
                }
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12, design: .monospaced))

                Button(
                    viewModel.isPATVisible ? "Hide Token" : "Show Token",
                    systemImage: viewModel.isPATVisible ? "eye.slash" : "eye"
                ) {
                    viewModel.isPATVisible.toggle()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)

                Button {
                    Task { await viewModel.validatePersonalAccessToken(modelContext: modelContext) }
                } label: {
                    HStack(spacing: 5) {
                        if viewModel.isValidatingPAT {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        Text("Validate & Connect")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.patInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isValidatingPAT)
            }
        }
        .padding(12)
        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.outlineVariant.opacity(0.45), lineWidth: 1)
        }
    }

    // MARK: - State B: Device Code Display

    private func codeDisplayStateView(_ response: GitHubDeviceCodeResponse) -> some View {
        VStack(spacing: 16) {
            Text("GitHub Device Authorization Code")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(OctoTheme.accentBlue)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(OctoTheme.accentBlue.opacity(0.15), in: .capsule)

            Text("Authorize OctoRunner")
                .font(.system(size: 20, weight: .bold))

            Text("Copy your one-time code below and enter it on GitHub's verification page.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                Text("YOUR ONE-TIME DEVICE CODE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text(response.userCode)
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(OctoTheme.accentBlue)
                        .textSelection(.enabled)

                    Button("Copy Code", systemImage: viewModel.copiedToClipboard ? "checkmark" : "doc.on.doc") {
                        viewModel.copyUserCode(response.userCode)
                    }
                    .buttonStyle(.bordered)
                }

                if viewModel.copiedToClipboard {
                    Text("✓ Copied to clipboard!")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(OctoTheme.onlineGreen)
                }
            }
            .padding(18)
            .frame(maxWidth: 430)
            .background(OctoTheme.surfaceLowest, in: .rect(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(OctoTheme.outlineVariant.opacity(0.6), lineWidth: 1)
            }

            HStack(spacing: 10) {
                Button {
                    viewModel.openVerificationPageAndStartPolling(response, modelContext: modelContext)
                } label: {
                    HStack(spacing: 6) {
                        Text("Copy Code & Open GitHub Verification Page")
                        Image(systemName: "arrow.up.right.square")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minHeight: 32)
                }
                .buttonStyle(.borderedProminent)
                .tint(OctoTheme.accentBlue)

                Button("Cancel", action: viewModel.cancelFlow)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    // MARK: - State C: Polling

    private func pollingStateView(_ response: GitHubDeviceCodeResponse) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
                .padding(12)

            Text("Waiting for browser authorization...")
                .font(.system(size: 19, weight: .bold))

            HStack(spacing: 6) {
                Circle()
                    .fill(OctoTheme.accentBlue)
                    .frame(width: 7, height: 7)
                Text("Code: \(response.userCode) • Checking github.com/login/device every \(response.interval)s...")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(OctoTheme.surfaceLow, in: .capsule)

            Text("Please confirm the code in your browser window. Once authorized, this sheet will complete automatically.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            HStack(spacing: 10) {
                Button("Re-open Browser") {
                    NSWorkspace.shared.open(response.verificationUri)
                }
                .buttonStyle(.bordered)

                Button("Cancel Authorization", role: .cancel, action: viewModel.cancelFlow)
                    .buttonStyle(.bordered)
            }
        }
        .padding(24)
    }

    // MARK: - State D: Authenticated

    private func successStateView(_ session: AuthenticatedGitHubSession) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 46))
                .foregroundStyle(OctoTheme.onlineGreen)

            Text("Connected Successfully!")
                .font(.system(size: 20, weight: .bold))

            Text("Authorized as @\(session.user.login)")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(OctoTheme.accentBlue)

            HStack(spacing: 10) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(OctoTheme.onlineGreen)
                VStack(alignment: .leading, spacing: 2) {
                    Text("macOS Keychain Updated")
                        .font(.system(size: 12, weight: .semibold))
                    Text("OAuth token stored with kSecAttrAccessibleWhenUnlockedThisDeviceOnly.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .frame(maxWidth: 430)
            .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 10))
            .overlay {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(OctoTheme.onlineGreen.opacity(0.35), lineWidth: 1)
            }

            Button {
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Text("Open Runner Pool Dashboard")
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 13, weight: .semibold))
                .frame(minWidth: 240, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .tint(OctoTheme.accentBlue)
        }
        .padding(24)
    }

    private var sheetFooterBar: some View {
        HStack {
            HStack(spacing: 6) {
                Circle()
                    .fill(OctoTheme.onlineGreen)
                    .frame(width: 6, height: 6)
                Text("Client ID: \(GitHubOAuthConfig.defaultClientID)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("Apple Silicon (arm64) native")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(OctoTheme.onlineGreen)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(OctoTheme.surfaceLowest)
    }
}
