import BackgroundMonitoringKit
import Foundation
import SyncKit
import Testing

struct LocalBackgroundMonitoringTests {
    @Test func onlyRegisteredProcessRootsAreObserved() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitoringSnapshotStore(directory: directory)
        let working = MonitoringRunnerDescriptor(id: UUID(), name: "Working", processRootPath: "/Users/example/Documents/Runner One")
        let waiting = MonitoringRunnerDescriptor(id: UUID(), name: "Waiting", processRootPath: "/runner-two")
        let disconnected = MonitoringRunnerDescriptor(id: UUID(), name: "Disconnected", processRootPath: "/runner-three")
        let unknown = MonitoringRunnerDescriptor(id: UUID(), name: "Unknown", processRootPath: nil)
        let configuration = MonitoringConfiguration(runners: [working, waiting, disconnected, unknown])
        try store.writeConfiguration(configuration)

        let monitor = LocalBackgroundMonitor(store: store, sampler: Sample([
            "/Users/example/Documents/Runner One": .init(listenerPID: 12, workerPID: 13),
            "/runner-two": .init(listenerPID: 14),
            "/runner-unregistered": .init(listenerPID: 15)
        ]))
        let now = Date(timeIntervalSince1970: 1_000)
        try await monitor.refresh(at: now)
        let observation = try #require(try store.readObservation(for: configuration, at: now))
        #expect(observation.statuses == [working.id: .busy, waiting.id: .idle, disconnected.id: .offline])
        #expect(observation.observedAt == now)
    }

    @Test func failedProcessMeasurementPublishesUnknownInsteadOfOffline() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitoringSnapshotStore(directory: directory)
        let runner = MonitoringRunnerDescriptor(id: UUID(), name: "Runner", processRootPath: "/runner")
        let configuration = MonitoringConfiguration(runners: [runner])
        try store.writeConfiguration(configuration)
        let now = Date(timeIntervalSince1970: 1_000)
        try store.writeObservation(.init(configurationRevision: configuration.revision, observedAt: now, statuses: [runner.id: .busy]))

        try await LocalBackgroundMonitor(store: store, sampler: FailingSample()).refresh(at: now)
        let observation = try #require(try store.readObservation(for: configuration, at: now))
        #expect(observation.statuses.isEmpty)
    }
}

private struct Sample: RunnerProcessSampling {
    let processes: [String: RunnerProcessPresence]
    init(_ processes: [String: RunnerProcessPresence]) { self.processes = processes }
    func sample() -> [String: RunnerProcessPresence] { processes }
}

private struct FailingSample: RunnerProcessSampling {
    func sample() throws -> [String: RunnerProcessPresence] { throw CocoaError(.fileReadUnknown) }
}
