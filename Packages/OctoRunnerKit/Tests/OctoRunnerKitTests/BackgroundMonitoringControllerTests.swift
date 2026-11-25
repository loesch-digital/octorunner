import AppShellFeature
import BackgroundMonitoringKit
import CoreModels
import Foundation
import Testing

@MainActor
struct BackgroundMonitoringControllerTests {
    @Test func approvedServiceGetsConfigurationOnlyForQuit() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitoringSnapshotStore(directory: directory)
        let controller = BackgroundMonitoringController(store: store, service: ServiceStub())
        let container = try OctoRunnerPersistence.makeInMemoryContainer()

        await controller.setEnabled(true)
        #expect(controller.state == .enabled)
        #expect(try store.readConfiguration() == nil)
        try await controller.prepareToQuit(in: container.mainContext, updating: false)
        #expect(try store.readConfiguration() != nil)
        await controller.resumeForeground()
        #expect(try store.readConfiguration() == nil)
    }

    @Test func disabledServiceAndUpdatesNeverHandOff() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MonitoringSnapshotStore(directory: directory)
        let service = ServiceStub()
        let controller = BackgroundMonitoringController(store: store, service: service)
        let container = try OctoRunnerPersistence.makeInMemoryContainer()

        try await controller.prepareToQuit(in: container.mainContext, updating: false)
        #expect(try store.readConfiguration() == nil)
        await controller.setEnabled(true)
        try await controller.prepareToQuit(in: container.mainContext, updating: true)
        #expect(try store.readConfiguration() == nil)
        #expect(await service.status() == .disabled)
    }
}

private actor ServiceStub: BackgroundMonitoringServicing {
    private var state = BackgroundMonitoringState.disabled

    func status() -> BackgroundMonitoringState { state }

    func setEnabled(_ enabled: Bool) {
        state = enabled ? .enabled : .disabled
    }
}
