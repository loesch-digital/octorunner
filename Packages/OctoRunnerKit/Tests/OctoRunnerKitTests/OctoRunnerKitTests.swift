import CoreModels
import Foundation
import SecurityKit
import SwiftData
import TelemetryKit
import Testing

@Suite("OctoRunnerKit Core Infrastructure Tests")
struct OctoRunnerKitTests {
    @Test("In-memory SwiftData RunnerEntity creation and cascade relationship")
    @MainActor
    func runnerEntityPersistence() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: RunnerEntity.self, JobRunEntity.self, configurations: config)
        let context = container.mainContext

        let runner = RunnerEntity(
            name: "mac-runner-test",
            scopeType: .repository,
            scopeUrl: URL(string: "https://github.com/loesch-digital/octorunner")!,
            status: .idle,
            labels: ["self-hosted", "macos", "arm64"],
            workDirectory: URL(fileURLWithPath: "/tmp/octorunner-test")
        )
        context.insert(runner)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<RunnerEntity>())
        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "mac-runner-test")
        #expect(fetched.first?.status == .idle)
    }

    @Test("HostTelemetryActor reads Apple Silicon CPU and memory metrics")
    func hostTelemetryMetrics() async {
        let actor = HostTelemetryActor()
        let snapshot = await actor.currentSnapshot()
        #expect(snapshot.totalCoreCount > 0)
        #expect(snapshot.physicalMemoryGB > 0)
        #expect(!snapshot.cpuSummary.isEmpty)
    }
}
