import AppKit
@testable import AppShellFeature
import CoreModels
import Foundation
@testable import GitHubAPI
import SwiftData
import SwiftUI
@testable import TelemetryKit
import Testing

@MainActor
struct HostTelemetryDashboardTests {
    @Test("Telemetry navigation identifies the hardware monitor")
    func navigation() {
        #expect(SidebarSection.hostTelemetry.title == "Host Telemetry")
        #expect(SidebarSection.hostTelemetry.systemImage == "waveform.path.ecg")
    }

    @Test("IO registry statistics reject missing or negative byte counters")
    func statistics() {
        #expect(SystemHostDiskIOSampler.counters(from: ["Bytes (Read)": NSNumber(value: 123), "Bytes (Write)": NSNumber(value: 456)]) == HostDiskIOCounters(readBytes: 123, writtenBytes: 456))
        #expect(SystemHostDiskIOSampler.counters(from: [:]) == nil)
        #expect(SystemHostDiskIOSampler.counters(from: ["Bytes (Read)": NSNumber(value: -1), "Bytes (Write)": NSNumber(value: 1)]) == nil)
    }

    @Test("API observations stay scoped to an account and older responses cannot overwrite new ones")
    func apiScope() {
        let budget = WorkflowHistoryRateBudget()
        let current = GitHubRateLimitSnapshot(headers: ["x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4900"], observedAt: Date(timeIntervalSince1970: 200))
        budget.observe(current, accountID: 7)
        #expect(budget.snapshot(for: 7) == current)
        #expect(budget.snapshot(for: 8) == nil)
        budget.observe(GitHubRateLimitSnapshot(headers: ["x-ratelimit-remaining": "1"], observedAt: Date(timeIntervalSince1970: 100)), accountID: 7)
        #expect(budget.snapshot(for: 7)?.remaining == 4900)
        budget.observe(nil, accountID: 7)
        #expect(budget.snapshot(for: 7)?.remaining == 4900)
    }

    @Test("Loaded history makes current account headers available after leaving Jobs")
    func observedHistory() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let budget = WorkflowHistoryRateBudget()
        let rate = GitHubRateLimitSnapshot(headers: ["x-ratelimit-remaining": "42"])
        let model = WorkflowHistoryViewModel(loader: TelemetryHistoryFixture(rate: rate), rateBudget: budget)
        try model.select(WorkflowHistorySelection(accountID: 7, keychainAccountKey: "fixture", repository: "example/repo"), in: container.mainContext)
        await model.load(in: container.mainContext)
        #expect(budget.snapshot(for: 7)?.remaining == 42)
        #expect(budget.snapshot(for: 8) == nil)
    }

    @Test("Pressure and thermal labels describe independent conditions and unavailable values in DE/EN")
    func conditionLabels() {
        let de = Locale(identifier: "de")
        let en = Locale(identifier: "en")
        #expect(HostTelemetryStatusText.memoryPressure(.normal, locale: en) == "Normal")
        #expect(HostTelemetryStatusText.memoryPressure(.warning, locale: en) == "Elevated")
        #expect(HostTelemetryStatusText.memoryPressure(.critical, locale: de) == "Kritisch")
        #expect(HostTelemetryStatusText.memoryPressure(nil, locale: de) == "Nicht verfügbar")
        #expect(HostTelemetryStatusText.thermalState(.nominal, locale: de) == "Normal")
        #expect(HostTelemetryStatusText.thermalState(.fair, locale: de) == "Leicht erhöht")
        #expect(HostTelemetryStatusText.thermalState(.serious, locale: en) == "High")
        #expect(HostTelemetryStatusText.thermalState(.critical, locale: en) == "Critical")
        #expect(HostTelemetryStatusText.thermalState(nil, locale: en) == "Unavailable")
    }

    @Test("Host cards render missing and real measurements at narrow/wide widths in DE/EN and Light/Dark")
    func rendering() async throws {
        for populated in [false, true] {
            let hostSnapshot: HostTelemetrySnapshot? = populated ? HostTelemetrySnapshot(cpuSummary: "Apple Silicon Test Host", totalCoreCount: 12, physicalMemoryGB: 32, usedMemoryGB: 12, osVersionString: "macOS", cpuUsagePercent: 45, performanceCoreCount: 8, efficiencyCoreCount: 4, memoryPressure: .warning, thermalState: .serious) : nil
            for language in ["de", "en"] {
                for width in [680.0, 1100.0] {
                    for scheme in [ColorScheme.light, .dark] {
                        let disk = HostDiskIOSnapshot(readBytesPerSecond: 125_000_000, writtenBytesPerSecond: 42_500_000)
                        let capacity = VolumeCapacitySnapshot(availableBytes: 250_000_000_000, totalBytes: 1_000_000_000_000)
                        let rate = GitHubRateLimitSnapshot(headers: ["x-ratelimit-limit": "5000", "x-ratelimit-remaining": "4900", "x-ratelimit-reset": "1800000000"])
                        let view = HostTelemetryCards(host: hostSnapshot, disk: populated ? disk : nil, capacity: populated ? capacity : nil, rate: populated ? rate : nil)
                            .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme)
                            .frame(width: width, height: 640)
                        let host = NSHostingView(rootView: view)
                        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 640), styleMask: [.titled], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false
                        window.contentView = host
                        for _ in 0..<5 { await Task.yield() }
                        host.layoutSubtreeIfNeeded()
                        #expect(host.fittingSize.width <= width)
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appending(path: "telemetry-\(populated)-\(language)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                        }
                        window.close()
                    }
                }
            }
        }
    }
}

private struct TelemetryHistoryFixture: WorkflowHistoryLoading {
    let rate: GitHubRateLimitSnapshot
    func page(selection: WorkflowHistorySelection, nextPage: URL?, completedAttempts: Set<String>) async throws -> WorkflowHistoryPage {
        WorkflowHistoryPage(runs: [], nextPage: nil, rateLimit: rate, observedAt: .now)
    }
}
