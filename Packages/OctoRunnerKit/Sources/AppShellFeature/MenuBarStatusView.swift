import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import SwiftData
import SwiftUI

public struct MenuBarStatusView: View {
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @Environment(\.openWindow) private var openWindow
    @Environment(\.locale) private var locale
    private let monitor: RunnerHealthMonitor?

    public init(monitor: RunnerHealthMonitor? = nil) { self.monitor = monitor }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerBar

            Divider()

            workpoolRunnersSection

            Divider()

            systemPoliciesSection

            Spacer(minLength: 4)

            Divider()

            footerBar
        }
        .padding(14)
        .frame(width: 350, height: 460)
        .background(OctoTheme.surfaceLowest)
    }

    // MARK: - Header

    private var headerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "infinity.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(OctoTheme.accentBlue)
                    .accessibilityHidden(true)
                Text("OctoRunner Engine")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Dashboard", systemImage: "macwindow") {
                    DashboardWindowCoordinator.activateOrOpenDashboard(openWindow: openWindow)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .accessibilityLabel("Open Dashboard Window")
                .accessibilityHint("Brings the existing OctoRunner dashboard window to the front")
            }

            TimelineView(.periodic(from: .now, by: 15)) { context in
                let health = monitor?.health(at: context.date) ?? .unknown
                Label(health.localizedTitle(locale: locale), systemImage: health.symbolName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OctoTheme.surface, in: .rect(cornerRadius: 6))
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Local runner status", bundle: .module))
        }
    }

    // MARK: - Runners List

    private var workpoolRunnersSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LOCAL WORKPOOL RUNNERS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            if runners.isEmpty {
                Text("No local runners configured yet.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
                    .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(runners) { runner in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(runner.name)
                                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                            .lineLimit(1)
                                        if let pid = runner.pid {
                                            Text("PID \(String(pid))")
                                                .font(.system(size: 10, design: .monospaced))
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(runner.scopeUrlString)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer()

                                RunnerStatusBadge(status: runner.status)
                            }
                            .padding(8)
                            .background(OctoTheme.surface, in: .rect(cornerRadius: 7))
                            .accessibilityElement(children: .combine)
                            .accessibilityLabel("Runner \(runner.name)")
                            .accessibilityValue("\(runner.status.badgeTitle), \(runner.scopeUrlString)")
                        }
                    }
                }
                .frame(maxHeight: 155)
            }
        }
    }

    // MARK: - Policies

    private var systemPoliciesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("AUTOSTART & SYSTEM POLICIES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.secondary)

            LoginItemSettingsControl()
                .toggleStyle(.checkbox)
                .font(.callout)
            SettingsLink {
                Text("Settings…", bundle: .module)
            }
            .accessibilityLabel(Text("Open OctoRunner settings", bundle: .module))
            .accessibilityHint(Text("Opens app preferences in a separate settings window.", bundle: .module))

            VStack(alignment: .leading, spacing: 6) {
                Text("Coming in v0.5.0 — not active yet")
                    .font(.caption)
                Toggle("Auto-restart Runner on Crash", isOn: .constant(false))
                    .accessibilityHint("Coming in v0.5.0; currently unavailable")
                Toggle("Pause Queue during Battery Saver", isOn: .constant(false))
                    .accessibilityHint("Coming in v0.5.0; currently unavailable")
            }
            .disabled(true)
            .toggleStyle(.checkbox)
            .font(.system(size: 11))
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OctoTheme.surface, in: .rect(cornerRadius: 8))
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            Text("OctoRunner v\(AppUpdaterActor.currentBundleVersion)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            Button("Hide Window", systemImage: "eye.slash") {
                DashboardWindowCoordinator.hideDashboardWindowToMenuBar()
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .help("Closes the Dashboard window while keeping OctoRunner active in the Menu Bar")
            .accessibilityLabel("Hide Dashboard Window to Menu Bar")

            Button("Quit", systemImage: "power", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
            .help("Quits OctoRunner and removes its menu bar item. Installed runner LaunchAgents continue running; imported runners may require migration.")
            .accessibilityLabel("Quit OctoRunner GUI")
        }
    }

}
