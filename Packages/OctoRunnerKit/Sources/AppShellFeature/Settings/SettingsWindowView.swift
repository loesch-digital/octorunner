import SwiftUI

public struct SettingsWindowView: View {
    @State private var selectedTab: SettingsTab = .general

    public init() {}

    public var body: some View {
        TabView(selection: $selectedTab) {
            Tab(value: SettingsTab.general) {
                GeneralSettingsTab()
            } label: {
                Label { Text("General", bundle: .module) } icon: { Image(systemName: "gearshape") }
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
