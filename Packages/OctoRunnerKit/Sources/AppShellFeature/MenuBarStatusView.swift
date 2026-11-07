import AppKit
import CoreModels
import DesignSystem
import GitHubAPI
import SwiftData
import SwiftUI

public struct MenuBarStatusView: View {
    @Query(sort: \RunnerEntity.name) private var runners: [RunnerEntity]
    @Environment(\.openWindow) private var openWindow

    @AppStorage("io.octorunner.policy.autostartLogin") private var autostartAtLogin: Bool = true
    @AppStorage("io.octorunner.policy.autoRestartCrash") private var autoRestartOnCrash: Bool = true
    @AppStorage("io.octorunner.policy.pauseBatterySaver") private var pauseOnBatterySaver: Bool = false

    public init() {}

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
                Text("OctoRunner Engine")
                    .font(.system(size: 13, weight: .bold))
                Spacer()
                Button("Dashboard", systemImage: "macwindow") {
                    openWindow(id: "main-dashboard")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            HStack(spacing: 6) {
                Circle()
                    .fill(activeOnlineCount > 0 ? OctoTheme.onlineGreen : .secondary)
                    .frame(width: 7, height: 7)
                Text("Background Engine active (\(activeOnlineCount)/\(runners.count) online)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(OctoTheme.surface, in: .rect(cornerRadius: 6))
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

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Autostart at macOS Login", isOn: $autostartAtLogin)
                Toggle("Auto-restart Runner on Crash", isOn: $autoRestartOnCrash)
                Toggle("Pause Queue during Battery Saver", isOn: $pauseOnBatterySaver)
            }
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

            Button("Quit OctoRunner", systemImage: "power", role: .destructive) {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
            .font(.system(size: 11, weight: .medium))
        }
    }

    private var activeOnlineCount: Int {
        runners.count(where: { $0.status == .idle || $0.status == .busy })
    }
}
