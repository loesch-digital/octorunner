import AppShellFeature
import CoreModels
import Foundation
import RunnerEngine
import SwiftData
import SyncKit
import Testing

@MainActor
struct RunnerHealthMonitorTests {
    private static var retainedContainers: [ModelContainer] = []

    @Test("A confirmed nonzero managed exit appears as faulted in fleet health")
    func directlyManagedFault() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let runnerRoot = root.appending(path: "runner", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runnerRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("exit 7\n".utf8).write(to: runnerRoot.appending(path: "run.sh"))
        let supervisor = RunnerSupervisorActor(processes: ManagedRunnerProcess(managedRoot: root))
        let context = container.mainContext
        let runner = RunnerEntity(name: "Managed", scopeUrl: URL(string: "https://github.com/example/repo")!,
            status: .offline, workDirectory: runnerRoot.appending(path: "_work"),
            rootDirectoryPath: runnerRoot.path, executionMode: .direct)
        context.insert(runner)
        try context.save()
        let id = runner.id
        try await supervisor.configure(.init(runnerID: id, name: "Managed", rootDirectory: runnerRoot, mode: .direct))
        try await supervisor.start(runnerID: id)
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await supervisor.snapshot(runnerID: id)?.phase != .faulted, .now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(await supervisor.snapshot(runnerID: id)?.lastExitStatus == 7)
        let notifications = AppNotificationsController(preferences: AppPreferencesStore(), client: HealthNotificationClient())
        let monitor = RunnerHealthMonitor(notifications: notifications, sampler: HealthProcessSampler(), supervisor: supervisor)
        await monitor.refresh(in: context)
        #expect(runner.status == .faulted)
        #expect(monitor.observations.first?.status == .faulted)
    }

    @Test("Health sampling updates the directly managed runner and invalidates failed measurements")
    func directlyManagedActivity() async throws {
        let container = try OctoRunnerPersistence.makeInMemoryContainer()
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let runnerRoot = root.appending(path: "runner", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: runnerRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("exec /bin/sleep 15\n".utf8).write(to: runnerRoot.appending(path: "run.sh"))
        let supervisor = RunnerSupervisorActor(processes: ManagedRunnerProcess(managedRoot: root))
        let id = UUID()
        try await supervisor.configure(.init(runnerID: id, name: "Managed", rootDirectory: runnerRoot, mode: .direct))
        try await supervisor.start(runnerID: id)
        let pid = try #require(await supervisor.snapshot(runnerID: id)?.pid)
        do {
            let notifications = AppNotificationsController(preferences: AppPreferencesStore(), client: HealthNotificationClient())
            let sampler = HealthProcessSampler()
            let monitor = RunnerHealthMonitor(notifications: notifications, sampler: sampler, supervisor: supervisor)
            await sampler.set([runnerRoot.path: RunnerProcessPresence(listenerPID: pid)])
            await monitor.refresh(in: container.mainContext)
            #expect(await supervisor.snapshot(runnerID: id)?.activity == .idle)
            await sampler.fail()
            await monitor.refresh(in: container.mainContext)
            #expect(await supervisor.snapshot(runnerID: id)?.activity == .unknown)
            try await supervisor.forceStop(runnerID: id)
        } catch {
            try? await supervisor.forceStop(runnerID: id)
            throw error
        }
    }

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
        await monitor.refresh(in: container.mainContext)
        #expect(await client.events.count == 3)
        #expect(await client.permissionRequests == 0)
        let audit = try container.mainContext.fetch(FetchDescriptor<AuditLogEntity>())
        #expect(audit.filter { $0.category == .runnerLifecycle }.count == 3)
        #expect(audit.contains { $0.targetRunnerName == "Build runner" && $0.severity == .warning })
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
