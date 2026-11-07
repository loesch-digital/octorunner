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

    private let oauthActor: GitHubOAuthActor
    private var pollingTask: Task<Void, Never>?

    public init(
        oauthActor: GitHubOAuthActor = GitHubOAuthActor(),
        initialState: AuthFlowState = .initial,
        copiedToClipboard: Bool = false
    ) {
        self.oauthActor = oauthActor
        self.state = initialState
        self.copiedToClipboard = copiedToClipboard
    }

    public func startDeviceFlow(modelContext: ModelContext, autoOpenBrowser: Bool = true) async {
        errorMessage = nil
        state = .requestingDeviceCode
        do {
            let response = try await oauthActor.requestDeviceCode()
            copyUserCode(response.userCode)
            if autoOpenBrowser {
                NSWorkspace.shared.open(response.verificationUri)
            }
            state = .polling(response)
            beginPolling(response, modelContext: modelContext)
        } catch is CancellationError {
            state = .initial
        } catch {
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
        modelContext: ModelContext
    ) {
        pollingTask?.cancel()
        pollingTask = Task {
            do {
                let session = try await oauthActor.pollForAccessToken(
                    deviceCode: response.deviceCode,
                    initialIntervalSeconds: response.interval
                )
                persistAccountSession(session, in: modelContext)
                state = .authenticated(session)
            } catch is CancellationError {
                // Cooperative cancellation on modal close or user cancel
            } catch {
                errorMessage = error.localizedDescription
                state = .initial
            }
        }
    }

    public func validatePersonalAccessToken(modelContext: ModelContext) async {
        errorMessage = nil
        isValidatingPAT = true
        defer { isValidatingPAT = false }

        do {
            let session = try await oauthActor.authenticateWithPersonalAccessToken(patInput)
            patInput = ""
            persistAccountSession(session, in: modelContext)
            state = .authenticated(session)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func cancelFlow() {
        pollingTask?.cancel()
        pollingTask = nil
        errorMessage = nil
        state = .initial
    }

    private func persistAccountSession(_ session: AuthenticatedGitHubSession, in modelContext: ModelContext) {
        let login = session.user.login
        let descriptor = FetchDescriptor<GitHubAccountEntity>(
            predicate: #Predicate<GitHubAccountEntity> { $0.login == login }
        )
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.displayName = session.user.name
            existing.avatarUrlString = session.user.avatarUrl
            existing.scopes = session.scopes
            existing.authMethodRaw = session.authMethod
            existing.connectedAt = .now
            existing.isActive = true
        } else {
            let entity = GitHubAccountEntity(
                githubUserId: session.user.id,
                login: session.user.login,
                displayName: session.user.name,
                avatarUrlString: session.user.avatarUrl,
                scopes: session.scopes,
                authMethodRaw: session.authMethod,
                keychainAccountKey: session.user.login,
                isActive: true
            )
            modelContext.insert(entity)
        }
        AuditLogRecorder.record(
            in: modelContext,
            category: .authentication,
            severity: .info,
            title: "GitHub Account Connected",
            summary: "Authenticated @\(session.user.login) via \(session.authMethod)",
            actorAccountLogin: session.user.login,
            newValue: session.scopes.joined(separator: ",")
        )
        try? modelContext.save()
    }
}
