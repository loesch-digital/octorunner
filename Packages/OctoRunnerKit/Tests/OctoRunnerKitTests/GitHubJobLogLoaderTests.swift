import Foundation
import CoreModels
import GitHubAPI
import Testing

struct GitHubJobLogLoaderTests {
    @Test("Job logs follow one validated HTTPS redirect with no credentials on the download request")
    func redirect() async throws {
        let transport = LogFixture(responses: [response(302, headers: ["Location": "https://logs.example.test/signed?fixture=private"]), response(200, text: "test ✓\n")])
        let snapshot = try await GitHubJobLogLoader(transport: transport).load(repository: "example/repo", jobID: 100, token: "synthetic")
        #expect(snapshot.snapshot.text == "test ✓\n" && !snapshot.snapshot.isTruncated)
        let requests = await transport.requests
        #expect(requests.count == 2)
        #expect(requests.first?.url?.path == "/repos/example/repo/actions/jobs/100/logs")
        #expect(requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic")
        #expect(requests.last?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests.last?.httpShouldHandleCookies == false)
    }

    @Test("Invalid redirect destinations never receive a request", arguments: ["http://logs.example.test/a", "https://user:secret@logs.example.test/a", "https://logs.example.test:8080/a", "file:///etc/passwd", "https://127.0.0.1/a", "https://localhost/a"])
    func unsafeRedirect(_ location: String) async {
        let transport = LogFixture(responses: [response(302, headers: ["Location": location])])
        await #expect(throws: GitHubJobLogError.self) { try await GitHubJobLogLoader(transport: transport).load(repository: "example/repo", jobID: 100, token: "synthetic") }
        #expect(await transport.requests.count == 1)
    }

    @Test("Permission, authentication, unavailable and rate responses retain typed status", arguments: [401, 403, 404, 410, 429, 500])
    func status(_ code: Int) async {
        let transport = LogFixture(responses: [response(code, headers: ["Retry-After": "30"])])
        do {
            _ = try await GitHubJobLogLoader(transport: transport).load(repository: "example/repo", jobID: 100, token: "synthetic")
            Issue.record("Expected status error")
        } catch GitHubActionsError.httpStatus(let actual, let rate) {
            #expect(actual == code && rate?.retryAfterSeconds == 30)
        } catch { Issue.record("Unexpected error type") }
    }

    @Test("Bounded UTF-8 logs trim only an incomplete final character and reject binary content")
    func boundedText() async throws {
        let limit = GitHubJobLogLoader.maximumBytes
        var data = Data(repeating: 65, count: limit - 1)
        data.append(contentsOf: "€".utf8)
        let transport = LogFixture(responses: [.init(statusCode: 200, headers: [:], data: data)])
        let snapshot = try await GitHubJobLogLoader(transport: transport).load(repository: "example/repo", jobID: 100, token: "synthetic")
        #expect(snapshot.snapshot.isTruncated && snapshot.snapshot.text.utf8.count == limit - 1)
        #expect(await transport.limits == [limit + 1])
        for binary in [Data(repeating: 65, count: limit - 1) + Data([0xff, 65]), Data([0, 1, 2]), Data([0x50, 0x4b, 3, 4]), Data([0xff, 0x61])] {
            let invalid = LogFixture(responses: [.init(statusCode: 200, headers: [:], data: binary)])
            await #expect(throws: GitHubJobLogError.self) { try await GitHubJobLogLoader(transport: invalid).load(repository: "example/repo", jobID: 100, token: "synthetic") }
        }
    }

    @Test("Invalid identity and pre-cancellation never send a request")
    func noRequest() async {
        let transport = LogFixture(responses: [])
        await #expect(throws: GitHubActionsError.self) { try await GitHubJobLogLoader(transport: transport).load(repository: "../repo", jobID: 0, token: "synthetic") }
        let task = Task { withUnsafeCurrentTask { $0?.cancel() }; return try await GitHubJobLogLoader(transport: transport).load(repository: "example/repo", jobID: 100, token: "synthetic") }
        _ = try? await task.value
        #expect(await transport.requests.isEmpty)
    }

    private func response(_ status: Int, headers: [String: String] = [:], text: String = "") -> GitHubActionsHTTPResponse {
        .init(statusCode: status, headers: headers, data: Data(text.utf8))
    }
}

private actor LogFixture: GitHubJobLogTransport {
    var requests: [URLRequest] = []
    var limits: [Int] = []
    private var responses: [GitHubActionsHTTPResponse]
    init(responses: [GitHubActionsHTTPResponse]) { self.responses = responses }
    func send(_ request: URLRequest, maximumBytes: Int) async throws -> GitHubActionsHTTPResponse {
        requests.append(request); limits.append(maximumBytes)
        guard !responses.isEmpty else { throw GitHubActionsError.invalidResponse }
        return responses.removeFirst()
    }
}
