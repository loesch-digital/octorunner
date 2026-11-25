import BackgroundMonitoringKit
import Foundation
import Observation
import SwiftData

@MainActor
@Observable
public final class BackgroundMonitoringController {
    public private(set) var state: BackgroundMonitoringState = .disabled
    public private(set) var isApplying = false
    public private(set) var hasError = false

    @ObservationIgnored private let store: MonitoringSnapshotStore
    @ObservationIgnored private let service: any BackgroundMonitoringServicing

    public init(
        store: MonitoringSnapshotStore = .init(directory: MonitoringStorage.directory),
        service: any BackgroundMonitoringServicing = BackgroundMonitoringService()
    ) {
        self.store = store
        self.service = service
    }

    public func refresh() async {
        guard !isApplying else { return }
        let state = await service.status()
        guard !isApplying else { return }
        self.state = state
    }

    public func setEnabled(_ enabled: Bool) async {
        guard !isApplying else { return }
        isApplying = true
        hasError = false
        defer { isApplying = false }
        do {
            if !enabled { try store.removeConfiguration() }
            try await service.setEnabled(enabled)
        } catch {
            hasError = true
        }
        state = await service.status()
    }

    public func resumeForeground() async {
        do { try store.removeConfiguration() }
        catch { hasError = true }
        await refresh()
    }

    public func prepareToQuit(in context: ModelContext, updating: Bool) async throws {
        guard !isApplying else { throw CocoaError(.fileWriteUnknown) }
        isApplying = true
        defer { isApplying = false }
        state = await service.status()
        if updating {
            try store.removeConfiguration()
            try await service.setEnabled(false)
            state = await service.status()
        } else if state == .enabled {
            let configuration = try MonitoringConfigurationExporter.configuration(in: context)
            try store.writeConfiguration(configuration)
        }
    }
}
