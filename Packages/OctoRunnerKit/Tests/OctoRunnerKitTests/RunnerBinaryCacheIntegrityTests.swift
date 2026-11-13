import CoreModels
import Foundation
import GitHubAPI
import RunnerEngine
import Testing

struct RunnerBinaryCacheIntegrityTests {
    @Test("Unavailable checksum resolution fails before creating cache folders or attempting an archive download")
    func missingTrustedChecksum() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "missing cache \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = offlineSession()
        defer { session.invalidateAndCancel() }
        let cache = RunnerBinaryCacheActor(cacheDirectory: root, urlSession: session, checksumResolver: FixtureArchiveChecksum(unavailable: true))
        await #expect(throws: GitHubRunnerChecksumError.checksumUnavailable) {
            try await cache.ensureBinaryDownloadedAndVerified(package: package)
        }
        #expect(!FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
    }

    @Test("A cached archive with missing API checksum is reused only after trusted resolution and byte verification")
    func verifiesCachedArchive() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "verified cache \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let archive = root.appending(path: package.filename)
        try Data("abc".utf8).write(to: archive)
        let session = offlineSession()
        defer { session.invalidateAndCancel() }
        let resolver = FixtureArchiveChecksum()
        let cache = RunnerBinaryCacheActor(cacheDirectory: root, urlSession: session, checksumResolver: resolver)
        #expect(try await cache.ensureBinaryDownloadedAndVerified(package: package) == archive)
        #expect(await resolver.calls == 1)
    }

    @Test("Download transport failures cannot expose private redirect credentials through the displayed error")
    func privateDownloadFailure() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "download error \(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = offlineSession()
        defer { session.invalidateAndCancel() }
        let cache = RunnerBinaryCacheActor(cacheDirectory: root, urlSession: session, checksumResolver: FixtureArchiveChecksum())
        do {
            _ = try await cache.ensureBinaryDownloadedAndVerified(package: package)
            Issue.record("The deliberately failing transport must not succeed")
        } catch {
            #expect(!error.localizedDescription.contains("synthetic-private-redirect-credential"))
        }
    }

    @Test("A real archive download is published only after matching its trusted digest", .timeLimit(.minutes(1)))
    func verifiedDownload() async throws {
        try await withArchiveServer { base in
            let root = FileManager.default.temporaryDirectory.appending(path: "download cache \(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let input = localPackage(base.appending(path: "good"))
            let cache = RunnerBinaryCacheActor(cacheDirectory: root, checksumResolver: FixtureArchiveChecksum())
            let result = try await cache.ensureBinaryDownloadedAndVerified(package: input)
            #expect(result == root.appending(path: input.filename))
            #expect(try Data(contentsOf: result) == Data("abc".utf8))
        }
    }

    @Test("A corrupted download cannot replace the existing cache file", .timeLimit(.minutes(1)))
    func corruptedDownloadPreservesCache() async throws {
        try await withArchiveServer { base in
            let root = FileManager.default.temporaryDirectory.appending(path: "corrupted cache \(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let input = localPackage(base.appending(path: "bad"))
            let archive = root.appending(path: input.filename)
            let previous = Data("previous-cache-payload".utf8)
            try previous.write(to: archive)
            let cache = RunnerBinaryCacheActor(cacheDirectory: root, checksumResolver: FixtureArchiveChecksum())
            do {
                _ = try await cache.ensureBinaryDownloadedAndVerified(package: input)
                Issue.record("Corrupt bytes must not pass verification")
            } catch RunnerEngineError.sha256Mismatch(let expected, let actual) {
                #expect(expected == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
                #expect(actual != expected)
            }
            #expect(try Data(contentsOf: archive) == previous)
        }
    }

    @Test("HTTP failures do not echo URL credentials and do not publish an archive", .timeLimit(.minutes(1)))
    func privateHTTPFailure() async throws {
        try await withArchiveServer { base in
            let root = FileManager.default.temporaryDirectory.appending(path: "http error cache \(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let input = localPackage(try #require(URL(string: base.absoluteString + "/failure?token=synthetic-http-credential")))
            let cache = RunnerBinaryCacheActor(cacheDirectory: root, checksumResolver: FixtureArchiveChecksum())
            do {
                _ = try await cache.ensureBinaryDownloadedAndVerified(package: input)
                Issue.record("HTTP errors must fail")
            } catch {
                #expect(!error.localizedDescription.contains("synthetic-http-credential"))
            }
            #expect(!FileManager.default.fileExists(atPath: root.appending(path: input.filename).path(percentEncoded: false)))
        }
    }

    private func localPackage(_ url: URL) -> GitHubRunnerDownloadDTO {
        // Only the metadata/HTTP boundary is replaced: the real downloader,
        // filesystem and SHA-256 validation remain under test.
        GitHubRunnerDownloadDTO(os: "osx", architecture: "arm64", downloadUrl: url, filename: package.filename)
    }

    private func withArchiveServer(_ body: (URL) async throws -> Void) async throws {
        let server = Process()
        let output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", Self.serverScript]
        server.standardOutput = output
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer {
            if server.isRunning { server.terminate() }
            server.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let text = try #require(String(data: output.fileHandleForReading.availableData, encoding: .utf8))
        let port = try #require(Int(text.trimmingCharacters(in: .whitespacesAndNewlines)))
        try await body(try #require(URL(string: "http://127.0.0.1:\(port)")))
    }

    private static let serverScript = #"""
    import os, threading
    from http.server import BaseHTTPRequestHandler, HTTPServer
    # A safety deadline bounds setup failures; assertions synchronize on the port.
    watchdog = threading.Timer(30, lambda: os._exit(0))
    watchdog.daemon = True
    watchdog.start()
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass
        def do_GET(self):
            body = b"abc" if self.path == "/good" else b"abd"
            status = 500 if self.path.startswith("/failure") else 200
            self.send_response(status)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    server.serve_forever()
    """#

    private var package: GitHubRunnerDownloadDTO {
        GitHubRunnerDownloadDTO(os: "osx", architecture: "arm64",
            downloadUrl: URL(string: "https://github.com/actions/runner/releases/download/v2.0.0/actions-runner-osx-arm64-2.0.0.tar.gz")!,
            filename: "actions-runner-osx-arm64-2.0.0.tar.gz")
    }

    private func offlineSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineArchiveProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private actor FixtureArchiveChecksum: GitHubRunnerChecksumResolving {
    private let unavailable: Bool
    private(set) var calls = 0
    init(unavailable: Bool = false) { self.unavailable = unavailable }
    func checksum(for package: GitHubRunnerDownloadDTO) throws -> SHA256Checksum {
        calls += 1
        if unavailable { throw GitHubRunnerChecksumError.checksumUnavailable }
        return SHA256Checksum("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")!
    }
}

private final class OfflineArchiveProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet,
            userInfo: [NSLocalizedDescriptionKey: "synthetic-private-redirect-credential"]))
    }
    override func stopLoading() {}
}
