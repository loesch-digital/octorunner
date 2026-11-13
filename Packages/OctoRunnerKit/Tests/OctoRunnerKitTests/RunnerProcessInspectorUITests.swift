import AppKit
@testable import AppShellFeature
import CoreModels
import Foundation
import SwiftData
import SwiftUI
import TelemetryKit
import Testing

@MainActor
struct RunnerProcessInspectorUITests {
    private func fixture() -> (RunnerProcessTarget, RunnerProcessMetadata) {
        let target = RunnerProcessTarget(id: UUID(), name: "Build Mac", rootPath: "/managed/mac")
        let metadata = RunnerProcessMetadata(identity: ProcessIdentity(pid: 42, startSeconds: 100, startMicroseconds: 0), parentPID: 1,
            userID: 501, executablePath: "/managed/mac/bin/Runner.Listener", cpuTimeSeconds: 2, residentBytes: 123_456_789)
        return (target, metadata)
    }

    @Test("Process inspector applies the selected runner filter and audits confirmed SIGTERM requests")
    func filterAndAudit() async throws {
        let (target, metadata) = fixture()
        let sample = RunnerProcessSample(uptime: 20, sampledAt: Date(timeIntervalSince1970: 200), processes: [metadata])
        let backend = InspectorBackend([sample])
        let model = RunnerProcessInspectorModel(monitor: RunnerProcessMonitor(backend: backend, userID: 501))
        await model.refresh(targets: [target])
        #expect(model.visibleProcesses.count == 1)
        model.selectedRunnerID = UUID()
        #expect(model.visibleProcesses.isEmpty)
        model.selectedRunnerID = target.id
        let row = try #require(model.visibleProcesses.first)
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        await model.terminate(row, targets: [target], context: container.mainContext)
        #expect(backend.signalled == [metadata.identity])
        let events = try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.targetRunnerName == "Build Mac" })
        #expect(events.contains { $0.title == "Process termination prepared" })
        #expect(events.contains { $0.title == "Process termination signal sent" })
        #expect(!model.isTerminating)
    }

    @Test("A changed process produces an audited refusal rather than a success")
    func failedTermination() async throws {
        let (target, metadata) = fixture()
        let backend = InspectorBackend([RunnerProcessSample(uptime: 20, sampledAt: .now, processes: [metadata])])
        let model = RunnerProcessInspectorModel(monitor: RunnerProcessMonitor(backend: backend, userID: 501))
        await model.refresh(targets: [target])
        let row = try #require(model.visibleProcesses.first)
        backend.replace(RunnerProcessSample(uptime: 21, sampledAt: .now, processes: []))
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        await model.terminate(row, targets: [target], context: container.mainContext)
        #expect(backend.signalled.isEmpty)
        #expect(model.operationFailed)
        #expect(try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>()).contains { $0.title == "Process termination refused or failed" })
    }

    @Test("Cancellation after a signal leaves a pending audit intent and avoids post-cancellation persistence")
    func cancelledOutcome() async throws {
        let (target, metadata) = fixture()
        let backend = InspectorBackend([RunnerProcessSample(uptime: 20, sampledAt: .now, processes: [metadata])])
        backend.cancelDuringSignal()
        let model = RunnerProcessInspectorModel(monitor: RunnerProcessMonitor(backend: backend, userID: 501))
        await model.refresh(targets: [target])
        let row = try #require(model.visibleProcesses.first)
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let task = Task { await model.terminate(row, targets: [target], context: container.mainContext) }
        await task.value
        #expect(backend.signalled == [metadata.identity])
        let events = try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(events.count == 1)
        #expect(events.first?.title == "Process termination prepared")
        #expect(!model.signalSent)
        #expect(!model.isTerminating)
    }

    @Test("Process cards render empty and populated lists and full details at narrow/wide widths in DE/EN Light/Dark")
    func rendering() async throws {
        let (target, metadata) = fixture()
        let row = InspectedRunnerProcess(runner: target, metadata: metadata, cpuPercent: 125, sampledAt: Date(timeIntervalSince1970: 200))
        for populated in [false, true] {
            for language in ["de", "en"] {
                for width in [680.0, 1100.0] {
                    for scheme in [ColorScheme.light, .dark] {
                        let content = RunnerProcessInspectorContent(processes: populated ? [row] : [], targets: [target], selectedRunnerID: .constant(nil),
                            samplingFailed: false, isTerminating: false, inspect: { _ in }, terminate: { _ in })
                            .environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme).frame(width: width, height: 540)
                        let host = NSHostingView(rootView: content)
                        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: 540), styleMask: [.titled], backing: .buffered, defer: false)
                        window.isReleasedWhenClosed = false; window.contentView = host
                        for _ in 0..<5 { await Task.yield() }
                        host.layoutSubtreeIfNeeded()
                        #expect(host.fittingSize.width <= width)
                        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LAYOUT_CAPTURE_DIR"] {
                            try #require(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path).appending(path: "processes-\(populated)-\(language)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                        }
                        window.close()
                    }
                }
            }
        }
        let detail = NSHostingView(rootView: RunnerProcessDetailView(process: row))
        detail.frame = CGRect(x: 0, y: 0, width: 600, height: 500)
        detail.layoutSubtreeIfNeeded()
        #expect(detail.bitmapImageRepForCachingDisplay(in: detail.bounds) != nil)
    }
}
