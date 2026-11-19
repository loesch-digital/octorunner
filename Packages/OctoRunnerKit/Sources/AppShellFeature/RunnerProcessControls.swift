import CoreModels
import DesignSystem
import RunnerEngine
import SwiftData
import SwiftUI

enum RunnerProcessControlAction: String, Identifiable {
    case start, drain, restart, forceStop, cancelRestart, releaseQuarantine

    var id: Self { self }

    static func available(phase: RunnerRuntimePhase, activity: RunnerActivity) -> [Self] {
        switch phase {
        case .stopped, .faulted: [.start]
        case .running: activity == .idle ? [.drain, .restart] : [.drain]
        case .drainTimedOut: [.drain, .forceStop]
        case .waitingToRestart, .waitingForPower: [.cancelRestart]
        case .quarantined: [.releaseQuarantine]
        case .starting, .stopping, .draining: []
        }
    }

    var title: String.LocalizationValue {
        switch self {
        case .start: "Start runner"
        case .drain: "Stop after current job"
        case .restart: "Restart runner"
        case .forceStop: "Force stop"
        case .cancelRestart: "Cancel pending start"
        case .releaseQuarantine: "Release and start runner"
        }
    }

    var hint: String.LocalizationValue {
        switch self {
        case .start: "Starts the runner under OctoRunner’s supervision."
        case .drain: "Stops the runner after a recent check confirms it is idle."
        case .restart: "Restarts an idle runner."
        case .forceStop: "May cancel a running job. Requires confirmation."
        case .cancelRestart: "Keeps the runner stopped."
        case .releaseQuarantine: "Clears the failure count and starts the runner."
        }
    }
}

struct RunnerProcessControls: View {
    @Environment(\.locale) private var locale
    @Environment(\.modelContext) private var context
    @State private var snapshot: RunnerRuntimeSnapshot?
    @State private var operation: Task<Void, Never>?
    @State private var message: String.LocalizationValue?
    @State private var confirmForce = false
    @State private var forceGeneration: UUID?

    let configuration: ManagedRunnerConfiguration
    let supervisor: RunnerSupervisorActor

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalization.string("Directly managed by OctoRunner", locale: locale))
                .font(.subheadline.weight(.semibold))
            if let snapshot, let pid = snapshot.pid, let startedAt = snapshot.startedAt {
                HStack {
                    Text(AppLocalization.string("Process group PID: \(String(pid))", locale: locale))
                    Spacer()
                    Text(AppLocalization.string("Uptime", locale: locale))
                    Text(startedAt, style: .timer).monospacedDigit()
                }
                .foregroundStyle(.secondary)
            }
            if snapshot?.phase == .draining {
                Text(AppLocalization.string("Waiting for the runner to become idle.", locale: locale))
                    .foregroundStyle(.secondary)
            } else if snapshot?.phase == .drainTimedOut {
                Text(AppLocalization.string("The wait ended. The runner is still active.", locale: locale))
                    .foregroundStyle(OctoTheme.warningOrange)
            } else if snapshot?.phase == .waitingToRestart {
                Text(AppLocalization.string("An automatic restart is scheduled.", locale: locale))
                    .foregroundStyle(OctoTheme.warningOrange)
            } else if snapshot?.phase == .waitingForPower {
                Text(AppLocalization.string("Start is deferred until Low Power Mode ends.", locale: locale))
                    .foregroundStyle(OctoTheme.warningOrange)
            } else if snapshot?.phase == .quarantined {
                Text(AppLocalization.string("Quarantined after repeated process failures.", locale: locale))
                    .foregroundStyle(OctoTheme.warningOrange)
            } else if snapshot?.phase == .faulted {
                Text(AppLocalization.string(snapshot?.lastExitStatus.map {
                    "Runner exit status: \(String($0))"
                } ?? "The runner could not start.", locale: locale))
                .foregroundStyle(OctoTheme.warningOrange)
                .textSelection(.enabled)
            }
            HStack {
                ForEach(RunnerProcessControlAction.available(phase: snapshot?.phase ?? .stopped,
                    activity: snapshot?.activity ?? .unknown)) { action in
                    let title = AppLocalization.string(action.title, locale: locale)
                    Button(title, role: action == .forceStop ? .destructive : nil) {
                        if action == .forceStop {
                            forceGeneration = snapshot?.generation
                            confirmForce = forceGeneration != nil
                        }
                        else { perform(action) }
                    }
                    .accessibilityLabel(title)
                    .accessibilityHint(AppLocalization.string(action.hint, locale: locale))
                }
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
        .confirmationDialog(AppLocalization.string("Force stop this runner?", locale: locale), isPresented: $confirmForce,
            titleVisibility: .visible) {
            Button(AppLocalization.string("Force stop", locale: locale), role: .destructive) { perform(.forceStop) }
            Button(AppLocalization.string("Cancel", locale: locale), role: .cancel) {}
        } message: {
            Text(AppLocalization.string("May cancel a running job. Requires confirmation.", locale: locale))
        }
        .task(id: configuration.runnerID) {
            while !Task.isCancelled {
                let next = await supervisor.snapshot(runnerID: configuration.runnerID)
                guard !Task.isCancelled else { return }
                snapshot = next
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onDisappear {
            operation?.cancel()
            operation = nil
        }
    }

    private func perform(_ action: RunnerProcessControlAction) {
        guard operation == nil else { return }
        let id = configuration.runnerID
        let expectedGeneration = forceGeneration
        let pendingGeneration = snapshot?.generation
        message = nil
        operation = Task {
            defer { if !Task.isCancelled { operation = nil } }
            do {
                switch action {
                case .start, .releaseQuarantine:
                    try await supervisor.configure(configuration)
                    try await supervisor.start(runnerID: id)
                case .drain:
                    try await supervisor.requestDrain(runnerID: id, timeout: .seconds(300))
                case .restart:
                    try await supervisor.restart(runnerID: id)
                case .forceStop:
                    guard let expectedGeneration else { return }
                    try await supervisor.forceStop(runnerID: id, expectedGeneration: expectedGeneration)
                case .cancelRestart:
                    guard let pendingGeneration else { return }
                    try await supervisor.cancelPendingStart(runnerID: id, expectedGeneration: pendingGeneration)
                }
                let next = await supervisor.snapshot(runnerID: id)
                guard !Task.isCancelled else { return }
                snapshot = next
                AuditLogRecorder.record(in: context, category: .runnerLifecycle,
                    title: "Runner Control",
                    summary: "\(configuration.name) (\(id.uuidString)): \(action.rawValue) → \(next?.phase.rawValue ?? "unknown")",
                    targetRunnerName: configuration.name)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                message = switch error as? RunnerSupervisionError {
                case .runnerBusy: "The runner is processing a job."
                case .activityUnknown: "The runner status has not been confirmed. Try again shortly."
                case .operationInProgress: "Another runner action is in progress."
                case .notManaged: "This runner could not be verified for direct control."
                default: "The runner action could not be completed."
                }
                AuditLogRecorder.record(in: context, category: .runnerLifecycle, severity: .warning,
                    title: "Runner Control Failed",
                    summary: "\(configuration.name) (\(id.uuidString)): \(action.rawValue)",
                    targetRunnerName: configuration.name)
            }
        }
    }
}
