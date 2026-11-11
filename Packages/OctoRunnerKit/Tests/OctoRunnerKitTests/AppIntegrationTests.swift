import AppShellFeature
import CoreModels
import Foundation
import RunnerEngine
import Testing

@MainActor
struct AppIntegrationTests {
    @Test("Login registration failure restores actual state and exposes an error")
    func loginFailure() async throws {
        let name = "octorunner-integration-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let service = TestLoginItemService(state: .disabled, fails: true)
        let controller = AppIntegrationController(preferences: preferences, loginService: service)
        preferences.launchAtLogin = true
        await controller.setLaunchAtLogin(true)
        #expect(!preferences.launchAtLogin)
        #expect(controller.loginState == .disabled)
        #expect(controller.errorMessage != nil)
        #expect(!controller.isApplyingLogin)
    }

    @Test("Pending OS approval is distinguished from an enabled login item")
    func loginApproval() async throws {
        let name = "octorunner-integration-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let service = TestLoginItemService(state: .disabled, registrationState: .requiresApproval)
        let controller = AppIntegrationController(preferences: preferences, loginService: service)
        await controller.setLaunchAtLogin(true)
        #expect(controller.loginState == .requiresApproval)
        #expect(!preferences.launchAtLogin)
    }

    @Test("Successful login changes persist and disabling really unregisters")
    func loginSuccess() async throws {
        let name = "octorunner-integration-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let service = TestLoginItemService(state: .disabled)
        let controller = AppIntegrationController(preferences: preferences, loginService: service)
        await controller.setLaunchAtLogin(true)
        #expect(preferences.launchAtLogin)
        #expect(AppPreferencesStore(defaults: defaults).launchAtLogin)
        await controller.setLaunchAtLogin(false)
        #expect(!preferences.launchAtLogin)
        #expect(await service.status() == .disabled)
    }

    @Test("Dock remains reachable when the menu bar item is hidden")
    func dockVisibility() {
        #expect(AppIntegrationController.shouldShowDock(hasVisibleDashboard: false, showInMenuBar: false, hideDockWhenClosed: true))
        #expect(AppIntegrationController.shouldShowDock(hasVisibleDashboard: true, showInMenuBar: true, hideDockWhenClosed: true))
        #expect(!AppIntegrationController.shouldShowDock(hasVisibleDashboard: false, showInMenuBar: true, hideDockWhenClosed: true))
        #expect(AppIntegrationController.shouldShowDock(hasVisibleDashboard: false, showInMenuBar: true, hideDockWhenClosed: false))
    }

    @Test("An older status refresh cannot overwrite a completed login change")
    func staleRefresh() async throws {
        let name = "octorunner-integration-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let (started, signal) = AsyncStream<Void>.makeStream()
        let service = DelayedLoginItemService(signal: signal)
        let controller = AppIntegrationController(preferences: preferences, loginService: service)
        let refresh = Task { await controller.refreshLoginState() }
        var iterator = started.makeAsyncIterator()
        _ = await iterator.next()
        await controller.setLaunchAtLogin(true)
        await service.releaseOldSnapshot()
        await refresh.value
        #expect(preferences.launchAtLogin)
        #expect(controller.loginState == .enabled)
    }
}

private actor DelayedLoginItemService: LoginItemServicing {
    private var state: LoginItemState = .disabled
    private var pending: CheckedContinuation<LoginItemState, Never>?
    private var blockFirstRead = true
    private let signal: AsyncStream<Void>.Continuation

    init(signal: AsyncStream<Void>.Continuation) { self.signal = signal }

    func status() async -> LoginItemState {
        if blockFirstRead {
            blockFirstRead = false
            signal.yield(())
            return await withCheckedContinuation { pending = $0 }
        }
        return state
    }
    func setEnabled(_ enabled: Bool) { state = enabled ? .enabled : .disabled }
    func releaseOldSnapshot() {
        pending?.resume(returning: .disabled)
        pending = nil
        signal.finish()
    }
}

private actor TestLoginItemService: LoginItemServicing {
    private var state: LoginItemState
    private let fails: Bool
    private let registrationState: LoginItemState

    init(state: LoginItemState, fails: Bool = false, registrationState: LoginItemState = .enabled) {
        self.state = state
        self.fails = fails
        self.registrationState = registrationState
    }
    func status() -> LoginItemState { state }
    func setEnabled(_ enabled: Bool) throws {
        if fails { throw CocoaError(.featureUnsupported) }
        state = enabled ? registrationState : .disabled
    }
}
