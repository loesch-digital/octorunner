import Foundation
import SyncKit
import Testing

struct RunnerProcessSamplerTests {
    @Test("System process metadata can be sampled without opening runner folders")
    func systemSample() async throws {
        _ = try await RunnerProcessSampler().sample()
    }

    @Test("Process sampling preserves spaces and matches executable paths rather than arguments")
    func processPaths() throws {
        let sample = """
          123 /Users/test/Runner Fleet/build runner/bin/Runner.Worker
          122 /Users/test/Runner Fleet/build runner/bin/Runner.Listener
          456 /Users/test/other/bin/Runner.Worker
          789 /usr/bin/editor Runner.Listener
          999 /tmp/bin/Runner.Listener.fake
        """
        let result = try RunnerProcessSampler.parseExecutableTable(sample)
        #expect(result.count == 2)
        #expect(result["/Users/test/Runner Fleet/build runner"]?.listenerPID == 122)
        #expect(result["/Users/test/Runner Fleet/build runner"]?.isWorkerActive == true)
        #expect(result["/Users/test/other"]?.listenerPID == nil)
        #expect(result["/Users/test/other"]?.isWorkerActive == true)
    }

    @Test("Empty or malformed process output is unavailable, never a successful all-offline sample")
    func invalidSamples() {
        #expect(throws: (any Error).self) { try RunnerProcessSampler.parseExecutableTable("") }
        #expect(throws: (any Error).self) { try RunnerProcessSampler.parseExecutableTable("permission denied") }
        #expect(throws: (any Error).self) { try RunnerProcessSampler.parseExecutableTable(" 1 /sbin/launchd\nmalformed") }
    }

    @Test("Runner self-updates keep versioned workers associated with their original runner root")
    func versionedBinaries() throws {
        let sample = """
          39169 /Users/test/Runner Fleet/actions-runner/bin.2.338.2/Runner.Worker
          87558 /Users/test/Runner Fleet/actions-runner/bin/Runner.Listener
          42000 /Users/test/second/bin.2.339.0/Runner.Listener
          42001 /Users/test/second/bin.2.339.0/Runner.Worker
          50001 /tmp/bin.cache/Runner.Worker
          50002 /tmp/bin.2.338.2.fake/Runner.Worker
          50003 /tmp/bin/Runner.Worker.fake
        """
        let result = try RunnerProcessSampler.parseExecutableTable(sample)
        #expect(result.count == 2)
        #expect(result["/Users/test/Runner Fleet/actions-runner"] == RunnerProcessPresence(listenerPID: 87558, workerPID: 39169))
        #expect(result["/Users/test/second"] == RunnerProcessPresence(listenerPID: 42000, workerPID: 42001))
    }
}
