import AppKit
import CoreModels
import Foundation
import GitHubAPI
import SecurityKit
import SwiftUI
import Testing
@testable import AppShellFeature

@MainActor
struct WorkflowJobLogTests {
    @Test("Creating and selecting a log view does not automatically download private logs")
    func explicitLoad() async {
        let fixture = JobLogModelTransport()
        let model = WorkflowJobLogModel(loader: .init(transport: fixture), secrets: JobLogSecrets())
        model.select(selection())
        #expect(await fixture.requests.isEmpty && model.snapshot == nil)
        await model.loadJobLog(selection: selection())
        #expect(model.snapshot?.text == "fixture output\n")
        #expect(await fixture.requests.count == 1)
    }

    @Test("Late log responses cannot cross cancellation, teardown or account changes", arguments: [0, 1, 2])
    func late(_ mode: Int) async {
        let fixture = JobLogModelTransport(gated: true)
        let model = WorkflowJobLogModel(loader: .init(transport: fixture), secrets: JobLogSecrets())
        let original = selection()
        model.select(original)
        let task = Task { await model.loadJobLog(selection: original) }
        await fixture.waitForRequest()
        if mode == 0 { model.invalidate() }
        if mode == 1 { model.select(selection(account: 8)) }
        if mode == 2 { task.cancel() }
        await fixture.release()
        await task.value
        #expect(model.snapshot == nil && model.error == nil && !model.isLoading)
    }

    @Test("Unavailable running logs and permission failures have distinct states", arguments: [401, 403, 404, 410, 429])
    func failures(_ status: Int) async {
        let fixture = JobLogModelTransport(status: status)
        let budget = WorkflowHistoryRateBudget()
        let model = WorkflowJobLogModel(loader: .init(transport: fixture), secrets: JobLogSecrets(), rateBudget: budget)
        model.select(selection())
        await model.loadJobLog(selection: selection())
        #expect(model.error != nil && model.snapshot == nil)
        if status == 404 || status == 410 { #expect(model.error == .notAvailable) }
        if status == 429 { #expect(budget.deadline(for: 7) != nil) }
    }

    @Test("A late log rate limit still belongs to its original account")
    func lateRateBudget() async {
        let fixture = JobLogModelTransport(gated: true, status: 429)
        let budget = WorkflowHistoryRateBudget()
        let model = WorkflowJobLogModel(loader: .init(transport: fixture), secrets: JobLogSecrets(), rateBudget: budget)
        let original = selection()
        model.select(original)
        let task = Task { await model.loadJobLog(selection: original) }
        await fixture.waitForRequest()
        model.select(selection(account: 8))
        await fixture.release()
        await task.value
        #expect(budget.deadline(for: 7) != nil && budget.deadline(for: 8) == nil)
        #expect(model.error == nil && model.snapshot == nil)
    }

    @Test("Log redirects preserve API budget and never attribute CDN limits to GitHub", arguments: [false, true])
    func redirectRateBudget(_ cdnLimited: Bool) async {
        let reset = Int(Date.now.addingTimeInterval(120).timeIntervalSince1970)
        var headers = ["Location": "https://logs.example.test/signed"]
        if !cdnLimited { headers["x-ratelimit-remaining"] = "0"; headers["x-ratelimit-reset"] = String(reset) }
        let fixture = JobLogModelTransport(responses: [
            .init(statusCode: 302, headers: headers, data: Data()),
            .init(statusCode: cdnLimited ? 429 : 200, headers: cdnLimited ? ["Retry-After": "30"] : [:], data: Data("output".utf8))
        ])
        let budget = WorkflowHistoryRateBudget()
        let model = WorkflowJobLogModel(loader: .init(transport: fixture), secrets: JobLogSecrets(), rateBudget: budget)
        model.select(selection())
        await model.loadJobLog(selection: selection())
        if cdnLimited {
            #expect(budget.deadline(for: 7) == nil && model.error == .unavailable)
        } else {
            #expect(budget.deadline(for: 7) != nil && model.snapshot?.text == "output")
            await model.loadJobLog(selection: selection())
            #expect(await fixture.requests.count == 2)
        }
    }

    @Test("Log view is readable at narrow and wide sizes without starting a download")
    func render() async {
        for language in ["de", "en"] {
            for width in [560.0, 960.0] {
                for scheme in [ColorScheme.light, .dark] {
                    let fixture = JobLogModelTransport(text: String(repeating: "2026-11-19 Step output: long workflow build result ✓ ", count: 40) + "\nFailed: example diagnostic\n")
                    let model = WorkflowJobLogModel(loader: .init(transport: fixture), secrets: JobLogSecrets())
                    model.select(selection())
                    await model.loadJobLog(selection: selection())
                    let root = WorkflowJobLogView(selection: selection(), model: model)
                        .environment(\.locale, Locale(identifier: language)).environment(\.colorScheme, scheme)
                    let host = NSHostingView(rootView: root)
                    host.frame = NSRect(x: 0, y: 0, width: width, height: 520)
                    host.layoutSubtreeIfNeeded()
                    #expect(host.fittingSize.width.isFinite)
                    if let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) {
                        host.cacheDisplay(in: host.bounds, to: bitmap)
                        #expect(bitmap.pixelsWide > 0)
                        if let path = ProcessInfo.processInfo.environment["OCTORUNNER_LOG_CAPTURE"],
                           let png = bitmap.representation(using: .png, properties: [:]) {
                            try? png.write(to: URL(filePath: path).appending(path: "job-log-\(language)-\(Int(width))-\(scheme == .dark ? "dark" : "light").png"))
                        }
                    }
                    #expect(await fixture.requests.count == 1)
                }
            }
        }
        #expect(AppLocalization.string("Load job log", locale: Locale(identifier: "de")) == "Job-Log laden")
    }

    @Test("VoiceOver exposes the downloaded text instead of only a generic log label")
    func accessibleOutput() async {
        let scroll = WorkflowJobLogTextView.makeScrollView(text: "Distinctive test failure line")
        let text = scroll.documentView as? NSTextView
        #expect(text?.isEditable == false && text?.isSelectable == true)
        #expect((text?.accessibilityValue() as? String)?.contains("Distinctive test failure line") == true)
    }

    private func selection(account: Int64 = 7) -> WorkflowJobLogSelection {
        .init(detail: .init(source: .init(accountID: account, keychainAccountKey: "fixture", repository: "example/repo"), runID: 42, attempt: 2), jobID: 100, jobName: "Build and Test")
    }
}

private struct JobLogSecrets: SecretReading {
    func readSecret(account: String, category: String) async throws -> String? { "synthetic" }
}

private actor JobLogModelTransport: GitHubJobLogTransport {
    private let gated: Bool
    private let status: Int
    private let text: String
    private let stream: AsyncStream<Void>
    private let started: AsyncStream<Void>.Continuation
    private var pending: CheckedContinuation<Void, Never>?
    private var responses: [GitHubActionsHTTPResponse]?
    var requests: [URLRequest] = []
    init(gated: Bool = false, status: Int = 200, text: String = "fixture output\n", responses: [GitHubActionsHTTPResponse]? = nil) {
        self.gated = gated; self.status = status; self.text = text; self.responses = responses
        (stream, started) = AsyncStream.makeStream()
    }
    func waitForRequest() async { for await _ in stream { return } }
    func release() { pending?.resume(); pending = nil }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> GitHubActionsHTTPResponse {
        requests.append(request)
        if gated && requests.count == 1 { await withCheckedContinuation { pending = $0; started.yield(()) } }
        if let response = responses?.first { responses?.removeFirst(); return response }
        return .init(statusCode: status, headers: status == 429 ? ["retry-after": "30"] : [:], data: Data(text.utf8))
    }
}
