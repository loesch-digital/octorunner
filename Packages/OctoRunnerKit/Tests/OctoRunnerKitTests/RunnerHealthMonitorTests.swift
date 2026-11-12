import AppShellFeature
import CoreModels
import Foundation
import SwiftData
import SyncKit
import Testing

@MainActor
struct RunnerHealthMonitorTests {
    private static var retainedContainers: [ModelContainer] = []

    @Test("Late process results after stop or cancellation cannot update SwiftData", arguments: [true, false])
    func lateResultIsDiscarded(stopMonitor: Bool) async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let runner = RunnerEntity(name: "Runner", scopeUrl: try #require(URL(string: "https://github.com/example/repo")),
            workDirectory: URL(fileURLWithPath: "/tmp/runner/_work"), rootDirectoryPath: "/tmp/runner")
        container.mainContext.insert(runner)
        try container.mainContext.save()
        let suite = "health-cancel-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        let sampler = GatedHealthSampler()
        let monitor = RunnerHealthMonitor(notifications: AppNotificationsController(preferences: preferences, client: HealthNotificationClient()), sampler: sampler)
        let refresh = Task { await monitor.refresh(in: container.mainContext) }
        await sampler.waitForStart()
        if stopMonitor { monitor.stop() } else { refresh.cancel() }
        await sampler.release()
        await refresh.value
        #expect(runner.status == .idle)
        #expect(runner.pid == nil)
        #expect(monitor.observations.isEmpty)
    }

    @Test("Live samples update tracked runners and publish only enabled transitions; errors stay unknown")
    func liveTransitions() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        Self.retainedContainers.append(container)
        let runner = RunnerEntity(name: "Build runner", scopeUrl: try #require(URL(string: "https://github.com/example/repo")),
            workDirectory: URL(fileURLWithPath: "/tmp/Runner Fleet/build/_work"), rootDirectoryPath: "/tmp/Runner Fleet/build")
        container.mainContext.insert(runner)
        try container.mainContext.save()
        let suite = "health-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = AppPreferencesStore(defaults: defaults)
        preferences.notificationPolicy.enabled = true
        preferences.notificationPolicy.runnerOnline = true
        preferences.notificationPolicy.runnerError = true
        let client = HealthNotificationClient()
        let notifications = AppNotificationsController(preferences: preferences, client: client)
        let sampler = HealthProcessSampler()
        let monitor = RunnerHealthMonitor(notifications: notifications, sampler: sampler)
        await sampler.set(["/tmp/Runner Fleet/build": RunnerProcessPresence(listenerPID: 42)])
        await monitor.refresh(in: container.mainContext)
        #expect(monitor.health(at: .now) == .healthy)
        #expect(runner.pid == 42 && runner.status == .idle)
        #expect(await client.events.isEmpty)
        await sampler.set([:])
        await monitor.refresh(in: container.mainContext)
        #expect(monitor.health(at: .now) == .offline)
        #expect(await client.events.map(\.kind) == [.runnerOffline])
        await monitor.refresh(in: container.mainContext)
        #expect(await client.events.count == 1)
        await sampler.set(["/tmp/Runner Fleet/build": RunnerProcessPresence(listenerPID: 43, workerPID: 44)])
        await monitor.refresh(in: container.mainContext)
        #expect(monitor.health(at: .now) == .busy)
        #expect(await client.events.map(\.kind) == [.runnerOffline, .runnerOnline])
        await sampler.fail()
        await monitor.refresh(in: container.mainContext)
        #expect(monitor.health(at: .now) == .unknown)
        #expect(runner.status == .busy)
        #expect(await client.events.count == 2)
        await sampler.set([:])
        await monitor.refresh(in: container.mainContext)
        #expect(await client.events.count == 2) // new baseline after unavailable observation
        runner.status = .faulted
        await monitor.refresh(in: container.mainContext)
        #expect(await client.events.map(\.kind) == [.runnerOffline, .runnerOnline, .runnerError])
        #expect(await client.permissionRequests == 0)
    }
}

private actor GatedHealthSampler: RunnerProcessSampling {
    private let started = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()
    func waitForStart() async {
        var iterator = started.stream.makeAsyncIterator()
        _ = await iterator.next()
    }
    func release() { gate.continuation.finish() }
    func sample() async -> [String: RunnerProcessPresence] {
        started.continuation.yield(())
        for await _ in gate.stream { }
        return ["/tmp/runner": RunnerProcessPresence(listenerPID: 10, workerPID: 11)]
    }
}

private actor HealthProcessSampler: RunnerProcessSampling {
    var value: [String: RunnerProcessPresence] = [:]
    var failed = false
    func set(_ value: [String: RunnerProcessPresence]) { self.value = value; failed = false }
    func fail() { failed = true }
    func sample() throws -> [String: RunnerProcessPresence] {
        if failed { throw CocoaError(.fileReadUnknown) }
        return value
    }
}

private actor HealthNotificationClient: AppNotificationClient {
    private(set) var events: [AppNotificationEvent] = []
    private(set) var permissionRequests = 0
    func authorizationStatus() -> NotificationAuthorizationState { .allowed }
    func requestAuthorization() -> Bool { permissionRequests += 1; return true }
    func deliver(_ event: AppNotificationEvent, soundEnabled: Bool) { events.append(event) }
}
