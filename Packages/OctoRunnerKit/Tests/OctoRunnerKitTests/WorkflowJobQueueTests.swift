import AppKit
import Foundation
import GitHubAPI
import SwiftUI
import Testing
@testable import AppShellFeature
@testable import SyncKit

@MainActor
struct WorkflowJobQueueTests {
    private let now = Date(timeIntervalSince1970: 1_000)
    private let account = RunnerSyncAccount(id: UUID(), credentialKey: "fixture", connectedAt: .distantPast)

    @Test("Queued job reports only current runners with every requested label in the matching repository")
    func matchingRunners() throws {
        let snapshot = try snapshot([
            ("busy", "https://github.com/example/repo", ["Self-Hosted", "ARM64"], "online", true),
            ("offline", "https://github.com/EXAMPLE/REPO", ["self-hosted", "arm64"], "offline", false),
            ("wrong-label", "https://github.com/example/repo", ["self-hosted"], "online", false),
            ("wrong-repo", "https://github.com/example/other", ["self-hosted", "arm64"], "online", false),
            ("organization", "https://github.com/example", ["self-hosted", "arm64"], "online", false)
        ])
        let diagnosis = try #require(diagnose(job: job(labels: ["self-hosted", "arm64"]), snapshot: snapshot))
        #expect(diagnosis.jobAge == 240)
        #expect(diagnosis.reason == .busyOrOffline)
        #expect(diagnosis.runners.map(\.name) == ["busy", "offline"])
        #expect(diagnosis.runners.map(\.state) == [.busy, .offline])
    }

    @Test("An idle match gives a limited observation and a missing timestamp leaves age unknown")
    func idleMatch() throws {
        let snapshot = try snapshot([("ready", "https://github.com/example/repo", ["self-hosted"], "online", false)])
        let diagnosis = try #require(diagnose(job: job(labels: ["self-hosted"], includeCreatedAt: false), snapshot: snapshot))
        #expect(diagnosis.reason == .idleMatch)
        #expect(diagnosis.runners.map(\.name) == ["ready"])
        #expect(diagnosis.jobAge == nil)
    }

    @Test("Stale job, stale runners, account changes and permissions never imply a routing cause")
    func unavailableEvidence() throws {
        let snapshot = try snapshot([("ready", "https://github.com/example/repo", ["self-hosted"], "online", false)])
        let job = try job(labels: ["self-hosted"])
        let stale = try #require(diagnose(job: job, snapshot: snapshot, jobObservedAt: now.addingTimeInterval(-91)))
        #expect(stale.reason == .staleJob)
        #expect(stale.jobAge == nil && stale.runners.isEmpty)

        let other = RunnerSyncAccount(id: UUID(), credentialKey: "other", connectedAt: .distantPast)
        for unavailable in [
            RunnerSyncSnapshot(account: other, observedAt: now, configurations: snapshot.configurations, results: snapshot.results),
            RunnerSyncSnapshot(account: account, observedAt: now.addingTimeInterval(-91), configurations: snapshot.configurations, results: snapshot.results),
            RunnerSyncSnapshot(account: account, observedAt: now, configurations: snapshot.configurations, results: snapshot.results.mapValues { _ in .forbidden })
        ] {
            let diagnosis = try #require(diagnose(job: job, snapshot: unavailable))
            #expect(diagnosis.reason == .runnerStatusUnavailable)
            #expect(diagnosis.runners.isEmpty)
        }
        let removed = try #require(diagnose(job: job, snapshot: snapshot, configurations: [:]))
        #expect(removed.reason == .runnerStatusUnavailable && removed.runners.isEmpty)
    }

    @Test("Jobs without confirmed self-hosted routing, or jobs that have a runner, omit the diagnosis")
    func unsupportedJobs() throws {
        for job in [
            try job(status: "in_progress", labels: ["self-hosted"]),
            try job(status: "waiting", labels: ["self-hosted"]),
            try job(labels: ["macos-latest"]),
            try job(labels: []),
            try job(labels: ["self-hosted"], runnerID: 1)
        ] {
            #expect(diagnose(job: job, snapshot: nil) == nil)
        }
    }

    @Test("Known runner data without matching labels does not claim the full GitHub inventory")
    func noMatch() throws {
        let snapshot = try snapshot([("mac", "https://github.com/example/repo", ["self-hosted"], "online", false)])
        let diagnosis = try #require(diagnose(job: job(labels: ["self-hosted", "mac-build"]), snapshot: snapshot))
        #expect(diagnosis.reason == .noKnownMatch)
        #expect(diagnosis.runners.isEmpty)
    }

    @Test("The queue hint renders in an expanded job card in German and English, Light and Dark")
    func rendering() throws {
        let snapshot = try snapshot([(String(repeating: "mac-build-", count: 12), "https://github.com/example/repo", ["self-hosted"], "online", true)])
        let job = try job(labels: ["self-hosted"])
        let diagnosis = try #require(diagnose(job: job, snapshot: snapshot))
        let selection = WorkflowRunDetailSelection(
            source: .init(accountID: 7, keychainAccountKey: "fixture", repository: "example/repo"),
            runID: 42, attempt: 1
        )
        for language in ["en", "de"] {
            for scheme in [ColorScheme.light, .dark] {
                let host = NSHostingView(rootView: WorkflowJobDetailCard(
                    job: job, selection: selection, now: now, queueDiagnosis: diagnosis
                ).environment(\.locale, Locale(identifier: language)).preferredColorScheme(scheme).frame(width: 460))
                host.frame.size = host.fittingSize
                host.layoutSubtreeIfNeeded()
                #expect(host.fittingSize.width == 460)
                let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
            }
        }
    }

    private func diagnose(job: GitHubWorkflowJobDTO, snapshot: RunnerSyncSnapshot?,
                          jobObservedAt: Date? = nil, configurations: [UUID: LocalDotRunnerConfig]? = nil) -> WorkflowJobQueueDiagnosis? {
        WorkflowJobQueueDiagnosis(job: job, repository: "example/repo", jobObservedAt: jobObservedAt ?? now,
                                  account: account, configurations: configurations ?? snapshot?.configurations ?? [:],
                                  snapshot: snapshot, now: now)
    }

    private func snapshot(_ runners: [(String, String, [String], String, Bool)]) throws -> RunnerSyncSnapshot {
        var configurations: [UUID: LocalDotRunnerConfig] = [:]
        var results: [UUID: RunnerLookupResult] = [:]
        for (offset, runner) in runners.enumerated() {
            let (name, scope, labels, status, busy) = runner
            let id = UUID()
            let remoteID = Int64(offset + 1)
            configurations[id] = .init(agentId: remoteID, agentName: name, gitHubUrl: try #require(URL(string: scope)))
            let data = try JSONSerialization.data(withJSONObject: [
                "id": remoteID, "name": name, "status": status, "busy": busy, "os": "macOS",
                "labels": labels.enumerated().map { ["id": $0.offset + 1, "name": $0.element, "type": "read-only"] }
            ])
            results[id] = .found(try JSONDecoder().decode(GitHubRemoteRunnerDTO.self, from: data), eTag: nil)
        }
        return RunnerSyncSnapshot(account: account, observedAt: now, configurations: configurations, results: results)
    }

    private func job(status: String = "queued", labels: [String], includeCreatedAt: Bool = true,
                     runnerID: Int64? = nil) throws -> GitHubWorkflowJobDTO {
        var payload: [String: Any] = ["id": 100, "run_id": 42, "name": "Build", "status": status, "labels": labels]
        if includeCreatedAt { payload["created_at"] = now.addingTimeInterval(-240).timeIntervalSinceReferenceDate }
        if let runnerID { payload["runner_id"] = runnerID }
        return try JSONDecoder().decode(GitHubWorkflowJobDTO.self, from: JSONSerialization.data(withJSONObject: payload))
    }
}
