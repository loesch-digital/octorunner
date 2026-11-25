import Foundation
import TelemetryKit
import Testing

struct RunnerWorkFolderMeasurerTests {
    @Test("Measures the configured directory recursively without following symbolic links")
    func configuredFolderSize() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        let work = root.appending(path: "custom-work")
        let checkout = work.appending(path: "checkout")
        let external = root.appending(path: "external")
        try files.createDirectory(at: checkout, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: root) }
        try files.createDirectory(at: external, withIntermediateDirectories: false)
        try Data(count: 16).write(to: work.appending(path: ".metadata"))
        try Data(count: 64).write(to: checkout.appending(path: "artifact"))
        try Data(count: 8_192).write(to: external.appending(path: "private-file"))
        try files.createSymbolicLink(at: checkout.appending(path: "external"), withDestinationURL: external)
        try files.createSymbolicLink(at: work.appending(path: "outside-file"), withDestinationURL: external.appending(path: "private-file"))
        let measurer = RunnerWorkFolderMeasurer()
        #expect(try await measurer.measure(path: work.path(percentEncoded: false)) == 80)
        #expect(try await measurer.measure(path: external.path(percentEncoded: false)) == 8_192)
    }

    @Test("Unsafe, missing, and symlink paths are not treated as empty work folders")
    func refusesInvalidRoots() async throws {
        let files = FileManager.default
        let root = files.temporaryDirectory.appending(path: UUID().uuidString)
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: root) }
        let link = root.appending(path: "link")
        try files.createSymbolicLink(at: link, withDestinationURL: root)
        let measurer = RunnerWorkFolderMeasurer()
        for path in ["", "_work", "/", "/tmp/..", link.path(percentEncoded: false), root.appending(path: "_work").path(percentEncoded: false)] {
            await #expect(throws: (any Error).self) {
                try await measurer.measure(path: path)
            }
        }
        #expect(try await measurer.measure(path: root.path(percentEncoded: false)) == 0)
    }
}
