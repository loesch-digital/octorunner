import DesignSystem
import Foundation
import GitHubAPI
import SwiftUI
import TelemetryKit

struct HostTelemetryCards: View {
    let host: HostTelemetrySnapshot?
    let disk: HostDiskIOSnapshot?
    let capacity: VolumeCapacitySnapshot?
    let rate: GitHubRateLimitSnapshot?
    @Environment(\.locale) private var locale

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16)], alignment: .leading, spacing: 16) {
            card("CPU Load", icon: "cpu") {
                Text(host?.cpuUsagePercent.map { number($0) + " %" } ?? "—").font(.largeTitle.monospacedDigit())
                    .accessibilityIdentifier("telemetry.cpuUsage")
                Text(host?.cpuSummary ?? "—").font(.headline)
                if let usage = host?.cpuUsagePercent { ProgressView(value: min(max(usage, 0), 100), total: 100).accessibilityLabel(Text("Total CPU load", bundle: .module)) }
                metric("Performance cores", value: host?.performanceCoreCount.map { $0.formatted(.number.locale(locale)) } ?? "—")
                metric("Efficiency cores", value: host?.efficiencyCoreCount.map { $0.formatted(.number.locale(locale)) } ?? "—")
                Text("Load covers all logical cores. Load by core type is unavailable.", bundle: .module).font(.caption).foregroundStyle(OctoTheme.secondaryText)
            }
            card("Unified Memory", icon: "memorychip") {
                Text(host?.usedMemoryGB.map { number($0) + " GiB" } ?? "—").font(.largeTitle.monospacedDigit())
                metric("Physical memory", value: host.map { number($0.physicalMemoryGB) + " GiB" } ?? "—")
                if let used = host?.usedMemoryGB, let total = host?.physicalMemoryGB, total > 0 {
                    ProgressView(value: min(max(used, 0), total), total: total).accessibilityLabel(Text("Used physical memory", bundle: .module))
                }
                metric("App memory", value: memory(host?.memory?.appBytes))
                metric("Wired memory", value: memory(host?.memory?.wiredBytes))
                metric("Compressed memory", value: memory(host?.memory?.compressedBytes))
                Text("Host-wide resident memory; filesystem cache size is a separate disk measurement.", bundle: .module).font(.caption).foregroundStyle(OctoTheme.secondaryText)
            }
            card("Storage & Device I/O", icon: "internaldrive") {
                Text(capacity.map { number(Double($0.availableBytes) / 1_073_741_824) + " GiB" } ?? "—").font(.largeTitle.monospacedDigit())
                Text("Available on home volume", bundle: .module).foregroundStyle(OctoTheme.secondaryText)
                metric("Volume capacity", value: capacity.map { number(Double($0.totalBytes) / 1_073_741_824) + " GiB" } ?? "—")
                metric("Device read", value: disk.map { number($0.readBytesPerSecond / 1_000_000) + " MB/s" } ?? "—")
                metric("Device write", value: disk.map { number($0.writtenBytesPerSecond / 1_000_000) + " MB/s" } ?? "—")
                Text("Throughput covers available host block devices, not an individual APFS volume. Storage analysis is in Cache & Storage settings.", bundle: .module).font(.caption).foregroundStyle(OctoTheme.secondaryText)
            }
            card("GitHub API", icon: "network") {
                Text(rate?.remaining.map { $0.formatted(.number.locale(locale)) } ?? "—").font(.largeTitle.monospacedDigit())
                metric("Request limit", value: rate?.limit.map { $0.formatted(.number.locale(locale)) } ?? "—")
                if let rate {
                    if let remaining = rate.remaining, let limit = rate.limit, limit > 0 {
                        ProgressView(value: Double(min(remaining, limit)), total: Double(limit)).accessibilityLabel(Text("Remaining API budget", bundle: .module))
                    }
                    if let reset = rate.resetAt {
                        LabeledContent { Text(reset, format: .dateTime.hour().minute().second()) } label: { Text("Resets at", bundle: .module) }
                    }
                    LabeledContent { Text(rate.observedAt, style: .relative) } label: { Text("Observation age", bundle: .module) }
                }
                Text("Last updated from Jobs for the active account. Open Jobs and refresh to retrieve the current API budget.", bundle: .module).font(.caption).foregroundStyle(OctoTheme.secondaryText)
            }
        }
        .tint(OctoTheme.accentBlue)
    }

    private func card<Content: View>(_ title: LocalizedStringKey, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label { Text(title, bundle: .module).font(.headline) } icon: { Image(systemName: icon).accessibilityHidden(true) }
                .accessibilityAddTraits(.isHeader)
            Divider()
            content()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20).background(OctoTheme.surface, in: .rect(cornerRadius: 12))
    }

    private func metric(_ title: LocalizedStringKey, value: String) -> some View {
        LabeledContent { Text(value).monospacedDigit() } label: { Text(title, bundle: .module).foregroundStyle(OctoTheme.secondaryText) }
    }
    private func number(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1)).locale(locale)) }
    private func memory(_ bytes: UInt64?) -> String { bytes.map { number(Double($0) / 1_073_741_824) + " GiB" } ?? "—" }
}
