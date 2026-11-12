import AppShellFeature
import CoreModels
import Foundation
import TelemetryKit
import Testing

@MainActor
struct DiskSpaceMonitorTests {
    private let gb: Int64 = 1_000_000_000

    @Test("Invalid volume capacities cannot become false low-space observations", arguments: [(-1, 100), (101, 100), (0, 0)])
    func invalidCapacity(_ values: (Int64, Int64)) {
        #expect(VolumeCapacitySnapshot(availableBytes: values.0, totalBytes: values.1) == nil)
    }

    @Test("Low space warns once per episode and requires two GB of recovery before rearming")
    func lowSpaceEpisodes() async throws {
        let environment = try DiskMonitorEnvironment()
        defer { environment.removeDefaults() }
        environment.preferences.notificationPolicy.enabled = true
        for (free, expectedCount) in [(30, 0), (20, 0), (19, 1), (18, 1), (21, 1), (22, 1), (19, 2)] {
            await environment.sampler.set(VolumeCapacitySnapshot(availableBytes: Int64(free) * gb, totalBytes: 100 * gb))
            await environment.monitor.refresh()
            #expect(await environment.client.events.count == expectedCount)
        }
        let events = await environment.client.events
        #expect(events.map(\.kind) == [.lowDiskSpace, .lowDiskSpace])
        #expect(events[0].id != events[1].id)
        #expect(await environment.client.permissionRequests == 0)
    }

    @Test("Unknown or stale capacity never sends an alert and does not rearm an existing warning")
    func unknownCapacity() async throws {
        let environment = try DiskMonitorEnvironment()
        defer { environment.removeDefaults() }
        environment.preferences.notificationPolicy.enabled = true
        await environment.sampler.set(VolumeCapacitySnapshot(availableBytes: 19 * gb, totalBytes: 100 * gb, observedAt: .now.addingTimeInterval(-120)))
        await environment.monitor.refresh()
        #expect(await environment.client.events.isEmpty)
        await environment.sampler.set(VolumeCapacitySnapshot(availableBytes: 19 * gb, totalBytes: 100 * gb))
        await environment.monitor.refresh()
        await environment.sampler.set(nil)
        await environment.monitor.refresh()
        await environment.sampler.set(VolumeCapacitySnapshot(availableBytes: 18 * gb, totalBytes: 100 * gb))
        await environment.monitor.refresh()
        #expect(await environment.client.events.count == 1)
    }

    @Test("Disk warnings obey both settings and can warn about current low space when explicitly enabled")
    func notificationSettings() async throws {
        let environment = try DiskMonitorEnvironment()
        defer { environment.removeDefaults() }
        await environment.sampler.set(VolumeCapacitySnapshot(availableBytes: 19 * gb, totalBytes: 100 * gb))
        await environment.monitor.refresh()
        #expect(await environment.client.events.isEmpty)
        environment.preferences.notificationPolicy.enabled = true
        environment.preferences.notificationPolicy.lowDiskSpace = false
        await environment.monitor.refresh()
        #expect(await environment.client.events.isEmpty)
        environment.preferences.notificationPolicy.lowDiskSpace = true
        await environment.monitor.refresh()
        #expect(await environment.client.events.count == 1)
        #expect(await environment.client.permissionRequests == 0)
    }

    @Test("A failed notification delivery retries without inventing another low-space episode")
    func deliveryRetry() async throws {
        let environment = try DiskMonitorEnvironment()
        defer { environment.removeDefaults() }
        environment.preferences.notificationPolicy.enabled = true
        await environment.sampler.set(VolumeCapacitySnapshot(availableBytes: 19 * gb, totalBytes: 100 * gb))
        await environment.client.setFailure(true)
        await environment.monitor.refresh()
        #expect(await environment.client.events.isEmpty)
        await environment.client.setFailure(false)
        await environment.monitor.refresh()
        await environment.monitor.refresh()
        #expect(await environment.client.events.count == 1)
    }

    @Test("Disabling alerts during a missing measurement still resets the warning for later explicit opt-in")
    func disabledWhileUnavailable() async throws {
        let environment = try DiskMonitorEnvironment()
        defer { environment.removeDefaults() }
        environment.preferences.notificationPolicy.enabled = true
        let low = VolumeCapacitySnapshot(availableBytes: 19 * gb, totalBytes: 100 * gb)
        await environment.sampler.set(low)
        await environment.monitor.refresh()
        environment.preferences.notificationPolicy.enabled = false
        await environment.sampler.set(nil)
        await environment.monitor.refresh()
        environment.preferences.notificationPolicy.enabled = true
        await environment.sampler.set(low)
        await environment.monitor.refresh()
        #expect(await environment.client.events.count == 2)
    }

    @Test("The capacity warning follows the selected German language and decimal number formatting")
    func germanCapacityWarning() async throws {
        let environment = try DiskMonitorEnvironment()
        defer { environment.removeDefaults() }
        environment.preferences.language = .german
        environment.preferences.notificationPolicy.enabled = true
        await environment.sampler.set(VolumeCapacitySnapshot(availableBytes: 19_500_000_000, totalBytes: 100 * gb))
        await environment.monitor.refresh()
        let event = try #require(await environment.client.events.first)
        #expect(event.message.contains("19,5 GB"))
        #expect(event.message.contains("verfügbar"))
        #expect(event.message.contains("20 GB"))
    }

    @Test("A capacity result arriving after stop or cancellation cannot publish", arguments: [true, false])
    func lateCapacity(stop: Bool) async throws {
        let sampler = GatedVolumeSampler()
        let environment = try DiskMonitorEnvironment(sampler: sampler)
        defer { environment.removeDefaults() }
        environment.preferences.notificationPolicy.enabled = true
        let task = Task { await environment.monitor.refresh() }
        await sampler.waitForStart()
        if stop { environment.monitor.stop() } else { task.cancel() }
        await sampler.release()
        await task.value
        #expect(await environment.client.events.isEmpty)
    }
}

@MainActor
private struct DiskMonitorEnvironment {
    let preferences: AppPreferencesStore
    let client: DiskNotificationClient
    let sampler = FixtureVolumeSampler()
    let monitor: DiskSpaceMonitor
    private let defaults: UserDefaults
    private let suite: String

    init(sampler injectedSampler: (any VolumeCapacitySampling)? = nil) throws {
        suite = "disk-monitor-\(UUID().uuidString)"
        defaults = try #require(UserDefaults(suiteName: suite))
        preferences = AppPreferencesStore(defaults: defaults)
        client = DiskNotificationClient()
        monitor = DiskSpaceMonitor(preferences: preferences,
            notifications: AppNotificationsController(preferences: preferences, client: client),
            sampler: injectedSampler ?? sampler)
    }

    func removeDefaults() { defaults.removePersistentDomain(forName: suite) }
}

private actor FixtureVolumeSampler: VolumeCapacitySampling {
    private var value: VolumeCapacitySnapshot?
    func set(_ value: VolumeCapacitySnapshot?) { self.value = value }
    func sample() -> VolumeCapacitySnapshot? { value }
}

private actor GatedVolumeSampler: VolumeCapacitySampling {
    private let started = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()
    func waitForStart() async { for await _ in started.stream { break } }
    func release() { gate.continuation.finish() }
    func sample() async -> VolumeCapacitySnapshot? {
        started.continuation.yield(())
        for await _ in gate.stream { }
        return VolumeCapacitySnapshot(availableBytes: 1_000_000_000, totalBytes: 100_000_000_000)
    }
}

private actor DiskNotificationClient: AppNotificationClient {
    private(set) var events: [AppNotificationEvent] = []
    private(set) var permissionRequests = 0
    private var failure = false
    func setFailure(_ value: Bool) { failure = value }
    func authorizationStatus() -> NotificationAuthorizationState { .allowed }
    func requestAuthorization() -> Bool { permissionRequests += 1; return true }
    func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) throws {
        if failure { throw CocoaError(.fileWriteUnknown) }
        events.append(event)
    }
}
