import CoreModels
import DesignSystem
import SwiftUI

public struct LoginItemSettingsControl: View {
    @Environment(AppPreferencesStore.self) private var preferences
    @Environment(AppIntegrationController.self) private var integration
    @State private var registrationTask: Task<Void, Never>?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading) {
            Toggle(isOn: loginBinding) {
                Text("Launch at macOS login", bundle: .module)
            }
            .disabled(integration.isApplyingLogin)
            .accessibilityLabel(Text("Launch at macOS login", bundle: .module))
            .accessibilityHint(Text("Registers OctoRunner as a login item for your macOS account.", bundle: .module))
            if integration.loginState == .requiresApproval {
                Text("Approve OctoRunner in System Settings → General → Login Items.", bundle: .module)
                    .foregroundStyle(OctoTheme.warningOrange)
            } else if integration.loginState == .unavailable {
                Text("Login items are unavailable for this app installation.", bundle: .module)
                    .foregroundStyle(.secondary)
            }
            if let message = integration.errorMessage {
                Text(message).foregroundStyle(OctoTheme.errorRed).textSelection(.enabled)
            }
        }
        .task { await integration.refreshLoginState() }
        .onDisappear { registrationTask?.cancel() }
    }

    // An asynchronous system write must reconcile its actual result, rather than
    // optimistically updating the saved preference through a normal binding.
    private var loginBinding: Binding<Bool> {
        Binding(get: { preferences.launchAtLogin }, set: changeRegistration)
    }

    private func changeRegistration(_ enabled: Bool) {
        registrationTask?.cancel()
        registrationTask = Task { await integration.setLaunchAtLogin(enabled) }
    }
}
