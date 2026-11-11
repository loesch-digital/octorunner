import CoreModels
import Observation
import RunnerEngine
import SwiftUI

@Observable
@MainActor
public final class AppIntegrationController {
    public private(set) var loginState: LoginItemState = .disabled
    public private(set) var isApplyingLogin = false
    public var errorMessage: String?

    @ObservationIgnored private let preferences: AppPreferencesStore
    @ObservationIgnored private let loginService: any LoginItemServicing
    @ObservationIgnored private var loginOperation = 0

    public init(preferences: AppPreferencesStore, loginService: any LoginItemServicing = RunnerSupervisorActor()) {
        self.preferences = preferences
        self.loginService = loginService
    }

    public func refreshLoginState() async {
        guard !isApplyingLogin else { return }
        loginOperation += 1
        let operation = loginOperation
        let actual = await loginService.status()
        guard !Task.isCancelled, !isApplyingLogin, operation == loginOperation else { return }
        loginState = actual
        preferences.launchAtLogin = actual == .enabled
    }

    public func setLaunchAtLogin(_ enabled: Bool) async {
        guard !isApplyingLogin else { return }
        loginOperation += 1
        isApplyingLogin = true
        errorMessage = nil
        defer { isApplyingLogin = false }
        do {
            let actual = await loginService.status()
            try Task.checkCancellation()
            if (actual == .enabled) != enabled || (actual == .requiresApproval && !enabled) {
                try await loginService.setEnabled(enabled)
            }
        } catch is CancellationError {
            // Registration may already have reached macOS; always reconcile its actual state.
        } catch {
            errorMessage = error.localizedDescription
        }
        let actual = await loginService.status()
        loginState = actual
        preferences.launchAtLogin = actual == .enabled
    }

    public static func shouldShowDock(hasVisibleDashboard: Bool, showInMenuBar: Bool, hideDockWhenClosed: Bool) -> Bool {
        hasVisibleDashboard || !showInMenuBar || !hideDockWhenClosed
    }

    public func applyDockVisibility(hasVisibleDashboard: Bool) {
        let show = Self.shouldShowDock(
            hasVisibleDashboard: hasVisibleDashboard,
            showInMenuBar: preferences.showInMenuBar,
            hideDockWhenClosed: preferences.hideDockIconWhenClosed
        )
        NSApplication.shared.setActivationPolicy(show ? .regular : .accessory)
    }
}
