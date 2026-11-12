import Foundation
import GitHubAPI
import Testing

struct GitHubActionsTransportTests {
    @Test("The production transport never follows HTTP redirects", .timeLimit(.minutes(1)))
    func rejectsRealRedirect() async throws {
        // Use the actual URLSession stack, not a mocked delegate invocation. The
        // server binds only to loopback and never receives real credentials.
        let server = Process()
        let output = Pipe()
        server.executableURL = URL(filePath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", Self.serverScript]
        server.standardOutput = output
        server.standardError = FileHandle.nullDevice
        try server.run()
        defer {
            if server.isRunning { server.terminate() }
            server.waitUntilExit()
            try? output.fileHandleForReading.close()
        }
        let portData = output.fileHandleForReading.availableData
        let portText = try #require(String(data: portData, encoding: .utf8))
        let port = try #require(Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)))
        let baseURL = try #require(URL(string: "http://127.0.0.1:\(port)"))
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let transport = GitHubActionsURLSessionTransport(session: session)
        var request = URLRequest(url: baseURL.appending(path: "redirect"))
        request.setValue("Bearer synthetic-fixture", forHTTPHeaderField: "Authorization")
        let response = try await transport.send(request)
        #expect(response.statusCode == 301)
        let (count, _) = try await session.data(from: baseURL.appending(path: "count"))
        #expect(String(data: count, encoding: .utf8) == "0")
    }

    private static let serverScript = #"""
    from http.server import BaseHTTPRequestHandler, HTTPServer

    class Handler(BaseHTTPRequestHandler):
        destinations = 0
        def log_message(self, *args):
            pass
        def do_GET(self):
            if self.path == "/redirect":
                self.send_response(301)
                self.send_header("Location", "http://127.0.0.1:%d/destination" % self.server.server_port)
                self.end_headers()
            elif self.path == "/destination":
                Handler.destinations += 1
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"unexpected redirect")
            elif self.path == "/count":
                self.send_response(200)
                self.end_headers()
                self.wfile.write(str(Handler.destinations).encode())
            else:
                self.send_error(404)

    server = HTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    server.serve_forever()
    """#
}
