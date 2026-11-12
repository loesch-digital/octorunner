import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import Observation
import SwiftData
import SwiftUI

public enum AuthFlowState: Equatable, Sendable {
    case initial
    case requestingDeviceCode
    case polling(GitHubDeviceCodeResponse)
    case authenticated(AuthenticatedGitHubSession)
}

@Observable
@MainActor
public final class OAuthDeviceFlowViewModel {
    public var state: AuthFlowState = .initial
    public var patInput: String = ""
    public var isPATVisible: Bool = false
    public var isValidatingPAT: Bool = false
    public var copiedToClipboard: Bool = false
    public var errorMessage: String?

    private let oauthActor: any GitHubAuthenticating
    private var pollingTask: Task<Void, Never>?
    private var deviceRequest: Task<GitHubDeviceCodeResponse, Error>?
    private var tokenRequest: Task<AuthenticatedGitHubSession, Error>?
    private var generation = 0

    public init(
        oauthActor: any GitHubAuthenticating = GitHubOAuthActor(),
        initialState: AuthFlowState = .initial,
        copiedToClipboard: Bool = false
    ) {
        self.oauthActor = oauthActor
        self.state = initialState
        self.copiedToClipboard = copiedToClipboard
    }

    public func startDeviceFlow(modelContext: ModelContext, autoOpenBrowser: Bool = true) async {
        guard !Task.isCancelled, !isValidatingPAT else { return }
        if case .requestingDeviceCode = state { return }
        generation += 1
        let revision = generation
        pollingTask?.cancel()
        deviceRequest?.cancel()
        tokenRequest?.cancel()
        errorMessage = nil
        state = .requestingDeviceCode
        do {
            let authenticator = oauthActor
            let request = Task { try await authenticator.requestDeviceCode(scopes: GitHubOAuthConfig.defaultScopes) }
            deviceRequest = request
            defer { if generation == revision { deviceRequest = nil } }
            let response = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: {
                request.cancel()
            }
            guard isCurrent(revision) else { return }
            copyUserCode(response.userCode)
            if autoOpenBrowser {
                NSWorkspace.shared.open(response.verificationUri)
            }
            state = .polling(response)
            beginPolling(response, modelContext: modelContext, revision: revision)
        } catch is CancellationError {
            if generation == revision { state = .initial }
        } catch {
            guard isCurrent(revision) else { return }
            errorMessage = error.localizedDescription
            state = .initial
        }
    }

    public func copyUserCode(_ code: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        copiedToClipboard = true
    }

    public func openVerificationPage(_ response: GitHubDeviceCodeResponse) {
        copyUserCode(response.userCode)
        NSWorkspace.shared.open(response.verificationUri)
    }

    private func beginPolling(
        _ response: GitHubDeviceCodeResponse,
        modelContext: ModelContext,
        revision: Int
    ) {
        pollingTask?.cancel()
        pollingTask = Task {
            do {
                let session = try await oauthActor.pollForAccessToken(
                    deviceCode: response.deviceCode,
                    initialIntervalSeconds: response.interval
                )
                try await finishAuthentication(session, revision: revision, in: modelContext)
            } catch is CancellationError {
                // Cooperative cancellation on modal close or user cancel
            } catch {
                guard isCurrent(revision) else { return }
                errorMessage = error.localizedDescription
                state = .initial
            }
        }
    }

    public func validatePersonalAccessToken(modelContext: ModelContext) async {
        guard !Task.isCancelled, !isValidatingPAT else { return }
        generation += 1
        let revision = generation
        let input = patInput
        pollingTask?.cancel()
        errorMessage = nil
        isValidatingPAT = true
        defer { if generation == revision { isValidatingPAT = false } }

        do {
            deviceRequest?.cancel()
            tokenRequest?.cancel()
            let authenticator = oauthActor
            let request = Task { try await authenticator.authenticateWithPersonalAccessToken(input) }
            tokenRequest = request
            defer { if generation == revision { tokenRequest = nil } }
            let session = try await withTaskCancellationHandler {
                try await request.value
            } onCancel: {
                request.cancel()
            }
            try await finishAuthentication(session, revision: revision, in: modelContext)
        } catch is CancellationError {
            return
        } catch {
            guard isCurrent(revision) else { return }
            errorMessage = error.localizedDescription
        }
    }

    public func cancelFlow() {
        generation += 1
        pollingTask?.cancel()
        pollingTask = nil
        deviceRequest?.cancel()
        deviceRequest = nil
        tokenRequest?.cancel()
        tokenRequest = nil
        patInput = ""
        isPATVisible = false
        isValidatingPAT = false
        copiedToClipboard = false
        errorMessage = nil
        state = .initial
    }

    private func isCurrent(_ revision: Int) -> Bool {
        !Task.isCancelled && revision == generation
    }

    isolated deinit {
        pollingTask?.cancel()
        deviceRequest?.cancel()
        tokenRequest?.cancel()
    }

    private func finishAuthentication(_ session: AuthenticatedGitHubSession, revision: Int, in modelContext: ModelContext) async throws {
        guard isCurrent(revision) else {
            try await oauthActor.discardSessionCredential(session)
            return
        }
        do {
            try GitHubAccountStore.upsert(session, in: modelContext)
        } catch {
            try await oauthActor.discardSessionCredential(session)
            throw error
        }
        patInput = ""
        state = .authenticated(session)
    }
}
