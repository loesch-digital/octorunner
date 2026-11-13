import Darwin
import Foundation
import Synchronization
import TelemetryKit
import Testing

struct RunnerProcessInspectorTests {
    private let runnerID = UUID()
    private func target(_ id: UUID? = nil, root: String = "/managed/mac") -> RunnerProcessTarget {
        RunnerProcessTarget(id: id ?? runnerID, name: "Build Mac", rootPath: root)
    }
    private func process(_ pid: Int32, parent: Int32 = 1, path: String = "/usr/bin/swift", start: UInt64 = 100,
                         uid: UInt32 = 501, cpu: Double? = 1) -> RunnerProcessMetadata {
        RunnerProcessMetadata(identity: ProcessIdentity(pid: pid, startSeconds: start, startMicroseconds: 0),
            parentPID: parent, userID: uid, executablePath: path, cpuTimeSeconds: cpu, residentBytes: 2048)
    }
    private func table(_ processes: [RunnerProcessMetadata], uptime: Double = 10) -> RunnerProcessSample {
        RunnerProcessSample(uptime: uptime, sampledAt: Date(timeIntervalSince1970: 200), processes: processes)
    }

    @Test("Only a uniquely owned runner binary and its same-user descendants are attributed")
    func association() async throws {
        let root = process(10, path: "/managed/mac/bin/Runner.Listener")
        let worker = process(11, parent: 10, path: "/managed/mac/bin.2.338.2/Runner.Worker")
        let swift = process(12, parent: 11)
        let unrelated = process(20, path: "/System/Library/CoreSimulatorService")
        let foreign = process(13, parent: 11, uid: 502)
        let fakeBinary = process(14, path: "/managed/mac/bin.fake/Runner.Listener")
        let backend = InspectorBackend([table([root, worker, swift, unrelated, foreign, fakeBinary])])
        let monitor = RunnerProcessMonitor(backend: backend, userID: 501)
        let result = try await monitor.snapshot(targets: [target()])
        #expect(result.map(\.metadata.identity.pid) == [10, 11, 12])
        #expect(result.allSatisfy { $0.runner.id == runnerID })
        #expect(result.first?.runtimeSeconds == 100)
        #expect(result.allSatisfy { $0.cpuPercent == nil })
    }

    @Test("Duplicate roots, malformed identities, cycles and newer parents cannot establish runner ownership")
    func ambiguousTrees() async throws {
        let root = process(10, path: "/managed/mac/bin/Runner.Listener")
        let backend = InspectorBackend([table([root, process(11, parent: 10)])])
        let monitor = RunnerProcessMonitor(backend: backend, userID: 501)
        #expect(try await monitor.snapshot(targets: [target(), target(UUID(), root: "/managed/mac/")]).isEmpty)
        backend.replace(table([root, process(11, parent: 12), process(12, parent: 11), process(13, parent: 10, start: 99), process(-1, parent: 10)]))
        #expect(try await monitor.snapshot(targets: [target()]).map(\.metadata.identity.pid) == [10])
        backend.replace(table([root, root, process(11, parent: 10)]))
        #expect(try await monitor.snapshot(targets: [target()]).isEmpty)
    }

    @Test("CPU uses monotonic deltas and resets for reused PIDs, missing counters and invalid intervals")
    func cpuDeltas() async throws {
        let path = "/managed/mac/bin/Runner.Listener"
        let backend = InspectorBackend([table([process(10, path: path)], uptime: 10)])
        let monitor = RunnerProcessMonitor(backend: backend, userID: 501)
        #expect(try await monitor.snapshot(targets: [target()]).first?.cpuPercent == nil)
        backend.replace(table([process(10, path: path, cpu: 1.5)], uptime: 12))
        #expect(try await monitor.snapshot(targets: [target()]).first?.cpuPercent == 25)
        backend.replace(table([process(10, path: path, cpu: 1.6)], uptime: 12))
        #expect(try await monitor.snapshot(targets: [target()]).first?.cpuPercent == nil)
        backend.replace(table([process(10, path: path, start: 101, cpu: 2)], uptime: 14))
        #expect(try await monitor.snapshot(targets: [target()]).first?.cpuPercent == nil)
        backend.replace(table([process(10, path: path, start: 101, cpu: nil)], uptime: 16))
        #expect(try await monitor.snapshot(targets: [target()]).first?.cpuPercent == nil)
        backend.replace(table([process(10, path: path, start: 101, cpu: 1)], uptime: 18))
        #expect(try await monitor.snapshot(targets: [target()]).first?.cpuPercent == nil)
        backend.replace(table([process(10, path: path, start: 101, cpu: 0.5)], uptime: 20))
        #expect(try await monitor.snapshot(targets: [target()]).first?.cpuPercent == nil)
    }

    @Test("Termination refuses reused PIDs or changed ancestry and signals only a freshly validated process")
    func termination() async throws {
        let root = process(10, path: "/managed/mac/bin/Runner.Listener")
        let child = process(11, parent: 10)
        let backend = InspectorBackend([table([root, child])])
        let monitor = RunnerProcessMonitor(backend: backend, userID: 501)
        let rows = try await monitor.snapshot(targets: [target()])
        let selected = try #require(rows.first { $0.metadata.identity.pid == 11 })
        backend.replace(table([root, process(11, parent: 10, start: 101)]))
        await #expect(throws: RunnerProcessError.self) { try await monitor.requestTermination(of: selected, targets: [target()]) }
        backend.replace(table([root, process(11, parent: 1)]))
        await #expect(throws: RunnerProcessError.self) { try await monitor.requestTermination(of: selected, targets: [target()]) }
        #expect(backend.signalled.isEmpty)
        backend.replace(table([root, child]))
        try await monitor.requestTermination(of: selected, targets: [target()])
        #expect(backend.signalled == [child.identity])
    }

    @Test("Cancelled inspection performs no system sampling or termination")
    func cancellation() async throws {
        let backend = InspectorBackend([table([])])
        let monitor = RunnerProcessMonitor(backend: backend, userID: 501)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await monitor.snapshot(targets: [target()])
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(backend.sampleCount == 0)
        #expect(backend.signalled.isEmpty)
    }

    @Test("Native SIGTERM targets only an isolated test-owned runner fixture")
    func nativeTermination() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).resolvingSymlinksInPath()
        let bin = root.appending(path: "bin", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let executable = bin.appending(path: "Runner.Listener")
        try Data(contentsOf: URL(fileURLWithPath: "/bin/sleep")).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path(percentEncoded: false))
        // A copied Apple platform signature is not valid at an arbitrary path (AMFI sends SIGKILL).
        // Sign the private fixture so this test observes our SIGTERM rather than an OS launch failure.
        let signer = Process()
        signer.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        signer.arguments = ["--force", "--sign", "-", executable.path(percentEncoded: false)]
        signer.standardOutput = FileHandle.nullDevice; signer.standardError = FileHandle.nullDevice
        try signer.run(); signer.waitUntilExit()
        try #require(signer.terminationStatus == 0)
        let fixture = Process()
        fixture.executableURL = executable; fixture.arguments = ["30"]
        try fixture.run()
        defer { if fixture.isRunning { fixture.terminate() }; fixture.waitUntilExit() }
        let runner = RunnerProcessTarget(id: UUID(), name: "Isolated test fixture", rootPath: root.path(percentEncoded: false))
        let monitor = RunnerProcessMonitor()
        let rows = try await monitor.snapshot(targets: [runner])
        let own = try #require(rows.first { $0.id.pid == fixture.processIdentifier })
        try await monitor.requestTermination(of: own, targets: [runner])
        fixture.waitUntilExit()
        #expect(fixture.terminationReason == .uncaughtSignal)
        #expect(fixture.terminationStatus == SIGTERM)
    }

    @Test("Native metadata identifies the current process without reading arguments or environment")
    func nativeMetadata() throws {
        let sample = try SystemRunnerProcessBackend().sample()
        let own = try #require(sample.processes.first { $0.identity.pid == getpid() })
        #expect(own.userID == geteuid())
        #expect(own.identity.startSeconds > 0)
        #expect(own.executablePath.hasPrefix("/"))
        #expect(own.cpuTimeSeconds.map { $0 >= 0 } ?? true)
    }
}

final class InspectorBackend: RunnerProcessBackend, Sendable {
    private struct State: Sendable {
        var samples: [RunnerProcessSample]
        var signalled: [ProcessIdentity] = []
        var count = 0
        var cancelOnSignal = false
    }
    private let state: Mutex<State>
    init(_ samples: [RunnerProcessSample]) { state = Mutex(State(samples: samples)) }
    func replace(_ sample: RunnerProcessSample) { state.withLock { $0.samples = [sample] } }
    func cancelDuringSignal() { state.withLock { $0.cancelOnSignal = true } }
    var sampleCount: Int { state.withLock { $0.count } }
    var signalled: [ProcessIdentity] { state.withLock { $0.signalled } }
    func sample() throws -> RunnerProcessSample {
        state.withLock { state in
            state.count += 1
            return state.samples.count > 1 ? state.samples.removeFirst() : state.samples[0]
        }
    }
    func requestTermination(of process: RunnerProcessMetadata) throws {
        let cancel = state.withLock { state in state.signalled.append(process.identity); return state.cancelOnSignal }
        if cancel { withUnsafeCurrentTask { $0?.cancel() } }
    }
}
