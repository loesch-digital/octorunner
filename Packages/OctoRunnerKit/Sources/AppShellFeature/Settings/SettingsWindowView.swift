import SwiftUI

public struct SettingsWindowView: View {
    @State private var selectedTab: SettingsTab = .general
    @State private var accountSession: AccountSessionController

    public init(accountSession: AccountSessionController = AccountSessionController()) {
        _accountSession = State(initialValue: accountSession)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: SettingsTab.general) {
                GeneralSettingsTab()
            } label: {
                Label { Text("General", bundle: .module) } icon: { Image(systemName: "gearshape") }
            }
            Tab(value: SettingsTab.background) {
                BackgroundSettingsTab()
            } label: {
                Label { Text("Autostart & Background", bundle: .module) } icon: { Image(systemName: "power") }
            }
            Tab(value: SettingsTab.failover) {
                FailoverSettingsTab()
            } label: {
                Label { Text("Failover", bundle: .module) } icon: { Image(systemName: "arrow.clockwise") }
            }
            Tab(value: SettingsTab.auth) {
                SecurityTokenSettingsTab(accountSession: accountSession)
            } label: {
                Label { Text("Auth & Tokens", bundle: .module) } icon: { Image(systemName: "key") }
            }
            Tab(value: SettingsTab.notifications) {
                AlertsSettingsTab()
            } label: {
                Label { Text("Notifications", bundle: .module) } icon: { Image(systemName: "bell") }
            }
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 480, idealHeight: 520)
    }
}
