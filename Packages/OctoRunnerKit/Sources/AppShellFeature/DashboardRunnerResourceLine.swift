import DesignSystem
import SwiftUI
import TelemetryKit

struct DashboardRunnerResourceLine<Status: View>: View {
    @Environment(\.locale) private var locale
    @State private var request: UUID?
    @State private var folderSize: Int64?
    @State private var measurementFailed = false

    let runnerName: String
    let usage: RunnerResourceUsage?
    let workFolderPath: String
    @ViewBuilder let status: () -> Status

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                status().fixedSize(horizontal: true, vertical: false)
                metrics
                workFolder
            }
            VStack(alignment: .leading, spacing: 6) {
                status()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        metrics
                        workFolder
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        metrics
                        workFolder
                    }
                }
            }
        }
        .font(.caption.monospaced())
        .foregroundStyle(OctoTheme.secondaryText)
        .task(id: request) { await measure(request, path: workFolderPath) }
        .onDisappear { request = nil }
        .onChange(of: workFolderPath) {
            request = nil
            folderSize = nil
            measurementFailed = false
        }
    }

    private var metrics: some View {
        HStack(spacing: 8) {
            if let cpu = usage?.cpuPercent {
                let value = (cpu / 100).formatted(.percent.precision(.fractionLength(0)).locale(locale))
                Text("CPU \(value)")
                    .help(AppLocalization.string("100% means one fully used logical CPU core.", locale: locale))
            }
            if let bytes = usage?.residentBytes {
                let value = Int64(clamping: bytes).formatted(.byteCount(style: .memory).locale(locale))
                Text("RAM \(value)")
                    .help(AppLocalization.string("Resident memory of detected runner processes.", locale: locale))
            }
        }
        .monospacedDigit()
        .fixedSize()
    }

    @ViewBuilder
    private var workFolder: some View {
        if workFolderPath.hasPrefix("/"), workFolderPath != "/" {
            if request != nil {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel(AppLocalization.string("Measuring Work Folder", locale: locale))
            } else if let folderSize {
                HStack(spacing: 6) {
                    Text(verbatim: URL(fileURLWithPath: workFolderPath).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(folderSize.formatted(.byteCount(style: .file).locale(locale))).fixedSize()
                    measureButton(iconOnly: true)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    if measurementFailed {
                        Text(AppLocalization.string("Could not measure the work folder.", locale: locale))
                    }
                    measureButton(iconOnly: false)
                }
            }
        }
    }

    private func measureButton(iconOnly: Bool) -> some View {
        let title = AppLocalization.string("Measure Work Folder", locale: locale)
        return Button {
            measurementFailed = false
            request = UUID()
        } label: {
            if iconOnly {
                Image(systemName: "arrow.clockwise")
            } else {
                Label(title, systemImage: "folder")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .help(title)
        .accessibilityLabel(AppLocalization.string("Measure Work Folder for \(runnerName)", locale: locale))
        .accessibilityHint(AppLocalization.string("Reads the size of files in this runner’s work folder.", locale: locale))
    }

    private func measure(_ token: UUID?, path: String) async {
        guard let token, !Task.isCancelled else { return }
        do {
            let bytes = try await RunnerWorkFolderMeasurer().measure(path: path)
            guard !Task.isCancelled, request == token else { return }
            folderSize = bytes
        } catch {
            guard !Task.isCancelled, request == token else { return }
            folderSize = nil
            measurementFailed = true
        }
        request = nil
    }
}
