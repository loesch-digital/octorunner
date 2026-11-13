import CoreModels
import Foundation
import Observation
import SwiftData
import TelemetryKit

@MainActor @Observable
final class RunnerProcessInspectorModel {
    private(set) var processes: [InspectedRunnerProcess] = []
    var selectedRunnerID: UUID?
    private(set) var samplingFailed = false
    private(set) var isTerminating = false
    private(set) var operationFailed = false
    private(set) var signalSent = false
    private let monitor: RunnerProcessMonitor

    init(monitor: RunnerProcessMonitor = RunnerProcessMonitor()) { self.monitor = monitor }

    var visibleProcesses: [InspectedRunnerProcess] {
        processes.filter { selectedRunnerID == nil || $0.runner.id == selectedRunnerID }
    }

    func refresh(targets: [RunnerProcessTarget]) async {
        guard !Task.isCancelled else { return }
        do {
            let next = try await monitor.snapshot(targets: targets)
            guard !Task.isCancelled else { return }
            processes = next; samplingFailed = false
        } catch is CancellationError { return }
        catch {
            guard !Task.isCancelled else { return }
            processes = []; samplingFailed = true
        }
    }

    func terminate(_ process: InspectedRunnerProcess, targets: [RunnerProcessTarget], context: ModelContext) async {
        guard !Task.isCancelled, !isTerminating else { return }
        isTerminating = true; operationFailed = false; signalSent = false
        defer { isTerminating = false }
        let summary = "\(process.name), PID \(process.id.pid), started \(process.id.startSeconds)."
        // An interrupted attempt remains explicitly pending; no success is inferred from this entry.
        context.insert(AuditLogEntity(category: .runnerLifecycle, severity: .warning, title: "Process termination prepared",
            summary: "Confirmed SIGTERM request prepared. No signal outcome recorded yet. \(summary)", targetRunnerName: process.runner.name))
        do { try context.save() }
        catch { operationFailed = true; return }
        var failed = false
        do { try await monitor.requestTermination(of: process, targets: targets) }
        catch is CancellationError { return }
        catch { failed = true }
        // Never touch SwiftData models/context after a cancelled sheet/task teardown.
        guard !Task.isCancelled else { return }
        context.insert(AuditLogEntity(category: .runnerLifecycle, severity: .warning,
            title: failed ? "Process termination refused or failed" : "Process termination signal sent",
            summary: failed ? "No termination confirmed. The process changed, became unavailable, or the request failed. \(summary)" :
                "SIGTERM was sent. Process exit is not confirmed; a service may restart it. \(summary)", targetRunnerName: process.runner.name))
        do { try context.save(); signalSent = !failed; operationFailed = failed }
        catch { operationFailed = true }
    }
}
