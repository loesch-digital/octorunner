@testable import AppShellFeature
import CoreModels
import Foundation
@testable import RunnerEngine
import Testing

struct RunnerConsolePresentationTests {
    @Test("Pausing freezes the visible logs and clearing excludes already received lines")
    func pauseAndClear() {
        func snapshot(_ ids: [Int]) -> RunnerLogSnapshot {
            let lines = ids.map { RunnerLogLine.parse("line \($0)", index: $0) }
            return .init(lines: lines, wasClipped: false, exportLines: lines)
        }
        var console = RunnerConsolePresentation()
        console.receive(snapshot([1]))
        console.togglePause()
        console.receive(snapshot([1, 2]))
        #expect(console.lines.map(\.id) == [1])
        console.clear()
        console.receive(snapshot([1, 2, 3]))
        #expect(console.lines.isEmpty)
        console.togglePause()
        #expect(console.lines.map(\.id) == [3])
    }

    @Test("Diagnostic export removes known credentials and private key blocks")
    func redactDiagnosticExport() {
        let snapshot = capture([
            "Started job", "Authorization: Basic encoded-credential", "remote ghp_sampletoken",
            "-----BEGIN OPENSSH PRIVATE KEY-----", "key-material", "-----END OPENSSH PRIVATE KEY-----",
            "api_key=credential", "Finished job",
        ])
        let export = RunnerConsoleExportDocument.formattedText(from: snapshot.exportLines)
        for secret in ["encoded-credential", "ghp_sampletoken", "key-material", "api_key=credential"] {
            #expect(!export.contains(secret))
        }
        #expect(export.contains("Started job") && export.contains("Finished job"))
    }

    @Test("Filtering cannot hide key boundaries from the exporter or leak a credential parsed as a timestamp")
    func redactionPrecedesPresentationFilter() {
        let snapshot = capture([
            "-----BEGIN OPENSSH PRIVATE KEY-----",
            "selected-key-material",
            "-----END OPENSSH PRIVATE KEY-----",
            "[ghp_secret] parsing failure",
            "finished",
        ])
        let export = RunnerConsoleExportDocument.formattedText(from: snapshot.exportLines, retaining: [2, 4, 5])
        #expect(!export.contains("selected-key-material"))
        #expect(!export.contains("ghp_secret"))
        #expect(export.contains("finished"))
        #expect(export.split(separator: "\n").count == 3)
    }

    private func capture(_ lines: [String]) -> RunnerLogSnapshot {
        var framer = RunnerLogByteFramer()
        var buffer = RunnerLogBuffer(maxLines: lines.count)
        buffer.append(framer.append(Data((lines.joined(separator: "\n") + "\n").utf8)))
        return buffer.snapshot
    }
}
