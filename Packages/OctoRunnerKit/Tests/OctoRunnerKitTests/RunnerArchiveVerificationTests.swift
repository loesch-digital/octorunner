import Foundation
import RunnerEngine
import Testing

struct RunnerArchiveVerificationTests {
    @Test("An absent or malformed SHA-256 checksum never verifies an archive", arguments: ["", "  \n", "abc", String(repeating: "z", count: 64)])
    func invalidChecksum(_ checksum: String) throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "absent-archive-\(UUID().uuidString)")
        // Invalid metadata must be rejected before opening even a missing file.
        #expect(try RunnerBinaryCacheActor.verifySHA256(of: file, expectedHex: checksum) == false)
    }

    @Test("Archive verification matches the standard SHA-256 abc vector and rejects altered bytes")
    func knownDigest() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "archive-vector-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        try Data("abc".utf8).write(to: file)
        #expect(try RunnerBinaryCacheActor.verifySHA256(of: file, expectedHex: digest))
        #expect(try RunnerBinaryCacheActor.verifySHA256(of: file, expectedHex: digest.uppercased()))
        try Data("abd".utf8).write(to: file)
        #expect(try RunnerBinaryCacheActor.verifySHA256(of: file, expectedHex: digest) == false)
    }

    @Test("Streaming verification matches the million-a SHA-256 vector across multiple file chunks")
    func multiChunkDigest() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "archive-large-vector-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 97, count: 1_000_000).write(to: file)
        #expect(try RunnerBinaryCacheActor.verifySHA256(of: file,
            expectedHex: "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"))
    }
}
