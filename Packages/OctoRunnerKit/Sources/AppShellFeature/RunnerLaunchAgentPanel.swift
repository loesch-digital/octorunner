import CoreModels
import DesignSystem
import RunnerEngine
import SwiftData
import SwiftUI

extension RunnerEntity {
    @MainActor
    var launchAgentTarget: RunnerLaunchAgentTarget? {
        guard !isImportedLocal, executionMode != .direct, executionMode != .external,
              let rootDirectoryPath, rootDirectoryPath.hasPrefix("/"), !serviceLabel.isEmpty else { return nil }
        let label = serviceLabel == "io.octorunner.agent.\(name)" ? RunnerServiceLabel.forRunner(named: name) : serviceLabel
        return .init(name: name, rootDirectory: URL(filePath: rootDirectoryPath), label: label)
    }
}

struct RunnerLaunchAgentPanel: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    @State private var diagnostic: RunnerLaunchAgentDiagnostic?
    @State private var runtime: RunnerLaunchAgentRuntime?
    @State private var operation: Task<Void, Never>?
    @State private var isLoading = false
    @State private var message: String.LocalizationValue?
    @State private var expanded = false

    let runnerID: UUID
    let target: RunnerLaunchAgentTarget
    let inspector: RunnerLaunchAgentInspector

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(target.label)
                .font(.callout.monospaced())
                .foregroundStyle(OctoTheme.secondaryText)
                .textSelection(.enabled)
            Text(AppLocalization.string(runtimeLabel, locale: locale))
                .font(.callout.weight(.semibold))

            if case let .running(pid, startedAt) = runtime {
                LabeledContent(AppLocalization.string("Service PID", locale: locale), value: String(pid))
                if let startedAt {
                    LabeledContent(AppLocalization.string("Uptime", locale: locale)) {
                        Text(startedAt, style: .timer).monospacedDigit()
                    }
                }
            }

            if let diagnostic {
                Text(AppLocalization.string(definitionLabel(diagnostic.definition), locale: locale))
                    .foregroundStyle(diagnostic.definition == .verified ? OctoTheme.onlineGreen : OctoTheme.secondaryText)
                if let xml = diagnostic.xml {
                    DisclosureGroup(AppLocalization.string("View launchd plist", locale: locale), isExpanded: $expanded) {
                        ScrollView([.horizontal, .vertical]) {
                            Text(verbatim: xml)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                                .padding(8)
                        }
                        .frame(height: 175)
                        .background(OctoTheme.surfaceLow, in: .rect(cornerRadius: 6))
                    }
                    .accessibilityHint(Text("Shows the installed plist as read-only XML.", bundle: .module))
                }
            }

            ViewThatFits(in: .horizontal) {
                HStack { buttons }
                VStack(alignment: .leading) { buttons }
            }
            .buttonStyle(.bordered)
            .disabled(operation != nil)

            if let message {
                Text(AppLocalization.string(message, locale: locale))
                    .foregroundStyle(OctoTheme.warningOrange)
                    .textSelection(.enabled)
            }
        }
        .font(.callout)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: target) { await refresh() }
        .onDisappear {
            guard !isLoading else { return }
            operation?.cancel()
            operation = nil
        }
    }

    @ViewBuilder private var buttons: some View {
        Button(AppLocalization.string("Refresh service status", locale: locale), systemImage: "arrow.clockwise") {
            run(loadDefinition: false)
        }
        .accessibilityHint(Text("Checks the installed definition and the current launchd service.", bundle: .module))
        if runtime == .unloaded, diagnostic?.definition == .verified {
            Button(AppLocalization.string("Load service", locale: locale), systemImage: "play.circle") {
                run(loadDefinition: true)
            }
            .accessibilityHint(Text("Loads the verified definition for the unloaded service.", bundle: .module))
        }
    }

    private var runtimeLabel: String.LocalizationValue {
        switch runtime {
        case .none: "Service status unavailable"
        case .unloaded: "Service unloaded"
        case .loaded: "Service loaded and stopped"
        case .unverified: "Service identity unverified"
        case .running: "Service running"
        }
    }

    private func definitionLabel(_ definition: RunnerLaunchAgentDefinition) -> String.LocalizationValue {
        switch definition {
        case .missing: "Installed plist not found"
        case .invalid: "Installed plist has invalid syntax"
        case .unverified: "Installed plist could not be verified"
        case .verified: "Verified plist syntax and ownership"
        }
    }

    private func refresh() async {
        do {
            let next = try await inspector.inspect(target)
            guard !Task.isCancelled else { return }
            diagnostic = next
            let service = try await inspector.runtime(target)
            guard !Task.isCancelled else { return }
            runtime = service
        } catch {
            guard !Task.isCancelled else { return }
            runtime = nil
        }
    }

    private func run(loadDefinition: Bool) {
        guard operation == nil else { return }
        message = nil
        isLoading = loadDefinition
        operation = Task {
            defer {
                if !Task.isCancelled {
                    operation = nil
                    isLoading = false
                }
            }
            if loadDefinition {
                do {
                    try await inspector.loadDefinition(target)
                    guard !Task.isCancelled else { return }
                    AuditLogRecorder.record(in: context, category: .runnerLifecycle,
                        title: "LaunchAgent Loaded", summary: "\(target.name) (\(runnerID.uuidString))",
                        targetRunnerName: target.name)
                } catch {
                    guard !Task.isCancelled else { return }
                    message = "The service could not be loaded. Check its current status."
                }
            }
            await refresh()
        }
    }
}
