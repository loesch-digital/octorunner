import Foundation
@testable import RunnerEngine
import Testing

struct RunnerConfigurationProcessTests {
    @Test("Verbose configuration completes instead of blocking on undrained output pipes")
    func verboseConfiguration() async throws {
        // The watchdog bounds the old deadlock, targeting only this fixture shell.
        // It is a safety deadline, not a timing assertion or synchronization delay.
        try await withScript("""
        fixture_pid=$$
        (sleep 5; kill -KILL "$fixture_pid") >/dev/null 2>&1 &
        watchdog=$!
        trap 'kill "$watchdog" 2>/dev/null' EXIT
        for ((i=0; i<32; i++)); do
            printf '%65536s\\n' x
            printf '%65536s\\n' y >&2
        done
        exit 0
        """) { root in
            try await configure(root)
        }
    }

    @Test("Configuration failures retain the exit status without exposing either output stream")
    func configurationFailureDoesNotExposeCredentials() async throws {
        try await withScript("""
        printf '%s\\n' 'synthetic-registration-secret' 'synthetic-private-output'
        printf '%s\\n' 'synthetic-registration-secret' 'synthetic-private-error' >&2
        exit 7
        """) { root in
            do {
                try await configure(root)
                Issue.record("A failed configuration must not report success")
            } catch RunnerEngineError.configurationFailed(let status, let detail) {
                #expect(status == 7)
                #expect(!detail.contains("synthetic-"))
                #expect(!RunnerEngineError.configurationFailed(status, detail).localizedDescription.contains("synthetic-"))
            }
        }
    }

    @Test("A cancelled configuration never launches the script")
    func cancelledConfigurationDoesNotLaunch() async throws {
        try await withScript("printf started > launched") { root in
            let task = Task {
                withUnsafeCurrentTask { $0?.cancel() }
                try await configure(root)
            }
            await #expect(throws: CancellationError.self) { try await task.value }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: "launched").path(percentEncoded: false)))
        }
    }

    private func configure(_ root: URL) async throws {
        try await RunnerProvisionerActor.runConfigScript(
            in: root, scopeURL: URL(string: "https://github.com/example/repository")!,
            registrationToken: "synthetic-registration-secret", runnerName: "fixture-runner",
            labels: ["fixture"], configuration: RunnerLaunchConfiguration()
        )
    }

    private func withScript(_ script: String, body: (URL) async throws -> Void) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "runner configuration \(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try script.write(to: root.appending(path: "config.sh"), atomically: true, encoding: .utf8)
        try await body(root)
    }
}
