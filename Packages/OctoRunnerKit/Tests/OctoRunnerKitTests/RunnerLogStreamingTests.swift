import Darwin
import Foundation
@testable import RunnerEngine
import Testing

struct RunnerLogStreamingTests {
    @Test("Private key bodies remain masked when the opening marker leaves the retained buffer")
    func redactionSurvivesEviction() {
        var decoder = RunnerLogByteFramer()
        var buffer = RunnerLogBuffer(maxLines: 2)
        buffer.append(decoder.append(Data("""
        -----BEGIN OPENSSH PRIVATE KEY-----
        key-material
        -----END OPENSSH PRIVATE KEY-----

        """.utf8)))
        #expect(buffer.snapshot.lines.map(\.message).contains("key-material"))
        #expect(buffer.snapshot.exportLines.map(\.message) == ["[REDACTED]", "[REDACTED]"])
    }

    @Test("Skipping an unknown byte prefix withholds export content until a known boundary")
    func redactUnknownBeginning() {
        var decoder = RunnerLogByteFramer()
        var buffer = RunnerLogBuffer(maxLines: 3)
        decoder.markExportContextUnknown()
        buffer.append(decoder.append(Data("missing-context\n-----END PRIVATE KEY-----\nsafe\n".utf8)))
        #expect(buffer.snapshot.exportLines.map(\.message) == ["[REDACTED]", "[REDACTED]", "safe"])
    }

    @Test("UTF-8 and CRLF survive split writes; an unfinished line is emitted at EOF")
    func fragmentedEncoding() {
        var decoder = RunnerLogByteFramer(maximumLineBytes: 128)
        let payload = Array("start 🐙\r\nend".utf8)
        #expect(decoder.append(Data(payload.prefix(7))).lines.isEmpty)
        #expect(decoder.append(Data(payload[7..<11])).lines.isEmpty)
        #expect(decoder.append(Data(payload.dropFirst(11))).lines == ["start 🐙"])
        #expect(decoder.finish().lines == ["end"])
        #expect(decoder.finish().lines.isEmpty)
    }

    @Test("Oversized lines are counted and skipped until the next newline")
    func boundedPartialLine() {
        var decoder = RunnerLogByteFramer(maximumLineBytes: 4)
        let first = decoder.append(Data("abcde".utf8))
        #expect(first.lines.isEmpty)
        #expect(first.discardedLineCount == 1)
        let second = decoder.append(Data("fg\r\nok\n".utf8))
        #expect(second.lines == ["ok"])
        #expect(second.discardedLineCount == 0)
    }

    @Test("Live service logs follow existing files, appends, truncation and replacement",
          .timeLimit(.minutes(1)))
    func liveServiceLog() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "octorunner-log-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "_diag")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stdout = directory.appending(path: "launchd.stdout.log")
        try Data("earliest\nsecond line\nlatest line\n".utf8).write(to: stdout)
        let stream = await RunnerLogStreamerActor().followFileLogs(
            forRunnerRoot: root, source: .launchAgent, maxLines: 2)
        var entries = stream.makeAsyncIterator()
        let initial = try #require(await entries.next())
        #expect(initial.lines.map(\.message) == ["second line", "latest line"])
        #expect(initial.wasClipped)

        let writer = try FileHandle(forWritingTo: stdout)
        defer { try? writer.close() }
        try writer.seekToEnd()
        try writer.write(contentsOf: Data("appended\n".utf8))
        let appended = try #require(await entries.next())
        #expect(appended.lines.map(\.message) == ["latest line", "appended"])

        try writer.truncate(atOffset: 0)
        try writer.seek(toOffset: 0)
        try writer.write(contentsOf: Data("replacement larger than the entire previous log in bytes\n".utf8))
        while let snapshot = await entries.next() {
            if snapshot.lines.last?.message == "replacement larger than the entire previous log in bytes" { break }
        }

        try Data("rotated\n".utf8).write(to: stdout, options: .atomic)
        while let snapshot = await entries.next() {
            if snapshot.lines.last?.message == "rotated" {
                #expect(snapshot.lines.first?.message == "replacement larger than the entire previous log in bytes")
                try writer.write(contentsOf: Data("late write through original handle\n".utf8))
                let rotatedWriter = try FileHandle(forWritingTo: stdout)
                defer { try? rotatedWriter.close() }
                try rotatedWriter.seekToEnd()
                try rotatedWriter.write(contentsOf: Data("rotation test boundary\n".utf8))
                var sawLateWrite = false
                while let update = await entries.next() {
                    sawLateWrite = sawLateWrite || update.lines.contains { $0.message == "late write through original handle" }
                    if update.lines.last?.message == "rotation test boundary" {
                        #expect(sawLateWrite)
                        return
                    }
                }
            }
        }
        Issue.record("Stream ended before delivering the rotated file")
    }

    @Test("An abandoned live log subscription closes its file descriptors")
    func abandonedSubscriptionClosesFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "octorunner-log-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = root.appending(path: "_diag")
        let stdout = directory.appending(path: "launchd.stdout.log")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("ready\n".utf8).write(to: stdout)
        var expected = stat()
        try #require(stat(stdout.path, &expected) == 0)
        let device = expected.st_dev
        let inode = expected.st_ino

        func readFirstSnapshot() async throws {
            let stream = await RunnerLogStreamerActor().followFileLogs(forRunnerRoot: root, source: .launchAgent)
            var updates = stream.makeAsyncIterator()
            let initial = try #require(await updates.next())
            #expect(initial.lines.map(\.message) == ["ready"])
            #expect(Self.isFileOpen(device: device, inode: inode))
        }

        try await readFirstSnapshot()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while Self.isFileOpen(device: device, inode: inode), .now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!Self.isFileOpen(device: device, inode: inode))
    }

    private static func isFileOpen(device: dev_t, inode: ino_t) -> Bool {
        let pid = getpid()
        let stride = MemoryLayout<proc_fdinfo>.stride
        let estimate = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard estimate > 0 else { return false }
        var descriptors = [proc_fdinfo](repeating: .init(), count: Int(estimate) / stride + 32)
        let size = descriptors.withUnsafeMutableBytes {
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count))
        }
        guard size > 0 else { return false }
        for entry in descriptors.prefix(Int(size) / stride) {
            var attributes = stat()
            if fstat(entry.proc_fd, &attributes) == 0, attributes.st_dev == device, attributes.st_ino == inode {
                return true
            }
        }
        return false
    }
}
