import DesignSystem
import SwiftUI

struct DashboardHostMetrics: View {
    @Environment(\.locale) private var locale

    let runnerCount: Int
    let activeRunnerCount: Int
    let hostDisplay: HostTelemetryDisplay

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], alignment: .leading, spacing: 12) {
            kpiCard(
                title: AppLocalization.string("Running Instances", locale: locale),
                value: AppLocalization.string("\(activeRunnerCount) of \(runnerCount) active", locale: locale),
                subtitle: activeRunnerCount > 0 ? AppLocalization.string("Supervised by Process Actor", locale: locale) : AppLocalization.string("Engine on standby", locale: locale),
                accent: activeRunnerCount > 0 ? OctoTheme.onlineGreen : .secondary
            )
            kpiCard(
                title: AppLocalization.string("Host CPU Architecture", locale: locale),
                value: hostDisplay.cpuBrand,
                subtitle: AppLocalization.string("\(hostDisplay.coreCount) logical cores", locale: locale),
                accent: OctoTheme.accentBlue
            )
            kpiCard(
                title: AppLocalization.string("Unified Memory", locale: locale),
                value: AppLocalization.string("\(hostDisplay.memoryCapacity) GiB RAM", locale: locale),
                subtitle: AppLocalization.string("\(hostDisplay.memoryUsed) GiB used", locale: locale),
                accent: OctoTheme.accentBlue
            )
        }
    }

    private func kpiCard(title: String, value: String, subtitle: String, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.primary)
            Text(subtitle)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(OctoTheme.surface, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(OctoTheme.outlineVariant.opacity(0.45), lineWidth: 1)
        }
    }
}

struct DashboardStatusBar: View {
    @Environment(\.locale) private var locale

    let engineIndicatorColor: Color
    let engineStatusText: String
    let hostDisplay: HostTelemetryDisplay

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Circle()
                    .fill(engineIndicatorColor)
                    .frame(width: 7, height: 7)
                Text(engineStatusText)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(AppLocalization.string("\(hostDisplay.cpuBrand) • \(hostDisplay.memoryCapacity) GiB Unified RAM", locale: locale))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .background(OctoTheme.surface)
    }
}
