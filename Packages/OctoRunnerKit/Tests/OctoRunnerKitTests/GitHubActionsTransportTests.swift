import Foundation
import GitHubAPI
import Testing

struct GitHubActionsTransportTests {
    @Test("The production transport never follows HTTP redirects", .timeLimit(.minutes(1)))
    func rejectsRealRedirect() async throws {
        // Use the actual URLSession stack, not a mocked delegate invocation. The
        // server binds only to loopback and never receives real credentials.
        try await withPythonTestServer(script: Self.serverScript) { baseURL in
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
