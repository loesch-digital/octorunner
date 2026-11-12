import CoreModels
import Foundation
import GitHubAPI
import SwiftData
import Testing
@testable import AppShellFeature

@MainActor
struct AuthCancellationTests {
    private static var containers: [ModelContainer] = []

    @Test("Closing PAT authentication rejects a late successful response without metadata writes")
    func latePAT() async throws {
        let context = try makeContext()
        let fixture = GatedAuthenticationFixture()
        let model = OAuthDeviceFlowViewModel(oauthActor: fixture)
        model.patInput = "synthetic-fixture"
        let task = Task { await model.validatePersonalAccessToken(modelContext: context) }
        await fixture.waitForRequest()
        model.cancelFlow()
        await fixture.releaseSession()
        await task.value
        #expect(await fixture.responseWasCancelled)
        #expect(await fixture.discardedCredentials == 1)
        #expect(model.state == .initial)
        #expect(model.patInput.isEmpty && !model.isValidatingPAT)
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AuditLogEntity>()) == 0)
    }

    @Test("A late device-code response cannot restart a cancelled dialog")
    func lateDeviceCode() async throws {
        let context = try makeContext()
        let fixture = GatedAuthenticationFixture()
        let model = OAuthDeviceFlowViewModel(oauthActor: fixture)
        let task = Task { await model.startDeviceFlow(modelContext: context, autoOpenBrowser: false) }
        await fixture.waitForRequest()
        model.cancelFlow()
        await fixture.releaseDeviceCode()
        await task.value
        #expect(await fixture.responseWasCancelled)
        #expect(model.state == .initial)
        #expect(!model.copiedToClipboard)
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 0)
    }

    @Test("A pre-cancelled PAT task never contacts the authenticator")
    func preCancelledPAT() async throws {
        let context = try makeContext()
        let fixture = GatedAuthenticationFixture(immediate: true)
        let model = OAuthDeviceFlowViewModel(oauthActor: fixture)
        model.patInput = "synthetic-fixture"
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            await model.validatePersonalAccessToken(modelContext: context)
        }
        await task.value
        #expect(await fixture.calls == 0)
        #expect(model.state == .initial)
        #expect(try context.fetchCount(FetchDescriptor<GitHubAccountEntity>()) == 0)
    }

    private func makeContext() throws -> ModelContext {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.containers.append(container)
        return container.mainContext
    }
}

private actor GatedAuthenticationFixture: GitHubAuthenticating {
    let immediate: Bool
    private var sessionResponse: CheckedContinuation<AuthenticatedGitHubSession, Error>?
    private var deviceResponse: CheckedContinuation<GitHubDeviceCodeResponse, Error>?
    private var started: CheckedContinuation<Void, Never>?
    private(set) var calls = 0
    private(set) var responseWasCancelled = false
    private(set) var discardedCredentials = 0
    func discardSessionCredential(_ session: AuthenticatedGitHubSession) async throws { discardedCredentials += 1 }
    init(immediate: Bool = false) { self.immediate = immediate }
    func requestDeviceCode(scopes: [String]) async throws -> GitHubDeviceCodeResponse {
        calls += 1
        let response: GitHubDeviceCodeResponse = try await withCheckedThrowingContinuation {
            deviceResponse = $0; started?.resume(); started = nil
        }
        responseWasCancelled = Task.isCancelled
        return response
    }
    func pollForAccessToken(deviceCode: String, initialIntervalSeconds: Int) async throws -> AuthenticatedGitHubSession {
        throw GitHubAuthError.accessDenied
    }
    func authenticateWithPersonalAccessToken(_ pat: String) async throws -> AuthenticatedGitHubSession {
        calls += 1
        if immediate { return session }
        let response: AuthenticatedGitHubSession = try await withCheckedThrowingContinuation {
            sessionResponse = $0; started?.resume(); started = nil
        }
        responseWasCancelled = Task.isCancelled
        return response
    }
    func waitForRequest() async {
        if sessionResponse != nil || deviceResponse != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func releaseSession() { sessionResponse?.resume(returning: session); sessionResponse = nil }
    func releaseDeviceCode() {
        deviceResponse?.resume(returning: GitHubDeviceCodeResponse(deviceCode: "synthetic-device", userCode: "TEST-CODE", verificationUri: URL(string: "https://github.com/login/device")!, expiresIn: 900, interval: 5))
        deviceResponse = nil
    }
    private var session: AuthenticatedGitHubSession {
        AuthenticatedGitHubSession(user: GitHubUserProfileDTO(id: 7, login: "fixture"), scopes: [], authMethod: "pat")
    }
}
