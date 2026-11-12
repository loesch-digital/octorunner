import CoreModels
import Foundation
import GitHubAPI
import Testing

struct RunnerChecksumResolverTests {
    private let digest = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private let filename = "actions-runner-osx-arm64-2.0.0.tar.gz"
    private let download = "https://github.com/actions/runner/releases/download/v2.0.0/actions-runner-osx-arm64-2.0.0.tar.gz"

    @Test("Missing download checksums resolve from the exact official release asset without sending credentials")
    func releaseDigest() async throws {
        let transport = ChecksumTransport(data: try fixture())
        let resolver = GitHubRunnerChecksumResolver(transport: transport)
        let checksum = try await resolver.checksum(for: package())
        #expect(checksum.hex == digest)
        let request = try #require(await transport.requests.first)
        #expect(request.url?.absoluteString == "https://api.github.com/repos/actions/runner/releases/tags/v2.0.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2026-03-10")
        _ = try await resolver.checksum(for: package())
        #expect(await transport.requests.count == 1)
    }

    @Test("A valid checksum in trusted download metadata needs no extra public API request")
    func suppliedDigest() async throws {
        let transport = ChecksumTransport(data: Data())
        let resolver = GitHubRunnerChecksumResolver(transport: transport)
        #expect(try await resolver.checksum(for: package(checksum: digest)).hex == digest)
        #expect(await transport.requests.isEmpty)
    }

    @Test("Archive paths and foreign download destinations are rejected before networking", arguments: [
        "../actions-runner-osx-arm64-2.0.0.tar.gz", "actions-runner-osx-arm64-2.0.0.tar.gz/extra",
        "https://example.com/runner.tar.gz", "https://github.com/actions/runner/releases/download/v2.0.0/actions-runner-osx-arm64-2.0.0.tar.gz?token=synthetic-secret"
    ])
    func invalidIdentity(_ value: String) async throws {
        let transport = ChecksumTransport(data: Data())
        let resolver = GitHubRunnerChecksumResolver(transport: transport)
        let input = value.hasPrefix("https:") ? package(url: value, checksum: digest) : package(filename: value, checksum: digest)
        await #expect(throws: GitHubRunnerChecksumError.invalidMetadata) {
            try await resolver.checksum(for: input)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("Wrong release or asset metadata never supplies a verification checksum", arguments: ["tag", "draft", "prerelease", "digest", "url", "duplicate", "missing", "missingDigest", "state", "malformedJSON"])
    func invalidRelease(_ mutation: String) async throws {
        let resolver = GitHubRunnerChecksumResolver(transport: ChecksumTransport(data: try fixture(mutation)))
        await #expect(throws: GitHubRunnerChecksumError.checksumUnavailable) {
            try await resolver.checksum(for: package())
        }
    }

    @Test("HTTP failures never expose response bodies or silently skip verification", arguments: [302, 403, 429, 500])
    func unavailableRelease(_ status: Int) async {
        let resolver = GitHubRunnerChecksumResolver(transport: ChecksumTransport(status: status, data: Data("synthetic-secret-response".utf8)))
        await #expect(throws: GitHubRunnerChecksumError.unavailable) {
            try await resolver.checksum(for: package())
        }
    }

    @Test("An already cancelled checksum lookup performs no network request")
    func cancelledLookup() async {
        let transport = ChecksumTransport(data: Data())
        let resolver = GitHubRunnerChecksumResolver(transport: transport)
        let input = package()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await resolver.checksum(for: input)
        }
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await transport.requests.isEmpty)
    }

    @Test("A lookup cancelled during HTTP cannot publish or cache its late checksum")
    func cancelledHTTPResult() async throws {
        let transport = GatedChecksumTransport(data: try fixture())
        let resolver = GitHubRunnerChecksumResolver(transport: transport)
        let input = package()
        let task = Task { try await resolver.checksum(for: input) }
        await transport.waitForStart()
        task.cancel()
        await transport.release()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(try await resolver.checksum(for: input).hex == digest)
        #expect(await transport.calls == 2)
    }

    @Test("Malformed supplied checksums fail before networking rather than being silently replaced")
    func malformedSuppliedChecksum() async {
        let transport = ChecksumTransport(data: Data())
        let resolver = GitHubRunnerChecksumResolver(transport: transport)
        await #expect(throws: GitHubRunnerChecksumError.invalidMetadata) {
            try await resolver.checksum(for: package(checksum: "not-a-checksum"))
        }
        #expect(await transport.requests.isEmpty)
    }

    private func package(filename: String? = nil, url: String? = nil, checksum: String? = nil) -> GitHubRunnerDownloadDTO {
        GitHubRunnerDownloadDTO(os: "osx", architecture: "arm64", downloadUrl: URL(string: url ?? download)!,
            filename: filename ?? self.filename, sha256Checksum: checksum)
    }

    private func fixture(_ mutation: String = "") throws -> Data {
        if mutation == "malformedJSON" { return Data("not-json".utf8) }
        var asset: [String: Any] = ["name": filename, "browser_download_url": download, "state": "uploaded", "digest": "sha256:\(digest)"]
        if mutation == "digest" { asset["digest"] = "sha256:not-a-checksum" }
        if mutation == "url" { asset["browser_download_url"] = "https://example.com/runner.tar.gz" }
        if mutation == "missingDigest" { asset.removeValue(forKey: "digest") }
        if mutation == "state" { asset["state"] = "new" }
        var release: [String: Any] = ["tag_name": mutation == "tag" ? "v1.0.0" : "v2.0.0",
            "draft": mutation == "draft", "prerelease": mutation == "prerelease", "assets": [asset]]
        if mutation == "duplicate" { release["assets"] = [asset, asset] }
        if mutation == "missing" { release["assets"] = [] }
        return try JSONSerialization.data(withJSONObject: release)
    }
}

private actor GatedChecksumTransport: GitHubActionsTransport {
    private let started = AsyncStream<Void>.makeStream()
    private let gate = AsyncStream<Void>.makeStream()
    private let data: Data
    private(set) var calls = 0
    init(data: Data) { self.data = data }
    func waitForStart() async { for await _ in started.stream { break } }
    func release() { gate.continuation.finish() }
    func send(_ request: URLRequest) async -> GitHubActionsHTTPResponse {
        calls += 1
        started.continuation.yield(())
        for await _ in gate.stream { }
        return GitHubActionsHTTPResponse(statusCode: 200, headers: [:], data: data)
    }
}

private actor ChecksumTransport: GitHubActionsTransport {
    private let status: Int
    private let data: Data
    private(set) var requests: [URLRequest] = []
    init(status: Int = 200, data: Data) { self.status = status; self.data = data }
    func send(_ request: URLRequest) -> GitHubActionsHTTPResponse {
        requests.append(request)
        return GitHubActionsHTTPResponse(statusCode: status, headers: [:], data: data)
    }
}
