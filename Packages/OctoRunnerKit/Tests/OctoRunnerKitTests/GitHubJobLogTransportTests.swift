import Foundation
import GitHubAPI
import Testing

struct GitHubJobLogTransportTests {
    @Test("Production byte transport bounds chunked output and refuses automatic redirects", .timeLimit(.minutes(1)))
    func streaming() async throws {
        try await withPythonTestServer(script: Self.script) { base in
            let session = URLSession(configuration: .ephemeral)
            defer { session.invalidateAndCancel() }
            let transport = GitHubJobLogURLSessionTransport(session: session)
            let response = try await transport.send(URLRequest(url: base.appending(path: "large")), maximumBytes: 4097)
            #expect(response.data.count == 4097 && response.data.allSatisfy { $0 == 65 })
            var request = URLRequest(url: base.appending(path: "redirect"))
            request.setValue("Bearer synthetic", forHTTPHeaderField: "Authorization")
            let redirect = try await transport.send(request, maximumBytes: 4097)
            #expect(redirect.statusCode == 302 && redirect.data.isEmpty)
            let (count, _) = try await session.data(from: base.appending(path: "count"))
            #expect(String(data: count, encoding: .utf8) == "0")
        }
    }
    private static let script = #"""
    from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
    class Handler(BaseHTTPRequestHandler):
        destinations = 0
        def log_message(self, *args): pass
        def do_GET(self):
            if self.path == "/redirect":
                self.send_response(302)
                self.send_header("Location", "http://127.0.0.1:%d/destination" % self.server.server_port)
                self.end_headers()
            elif self.path == "/large":
                self.send_response(200)
                self.end_headers()
                try:
                    for _ in range(1024): self.wfile.write(b"A" * 8192); self.wfile.flush()
                except (BrokenPipeError, ConnectionResetError): pass
            elif self.path == "/count":
                self.send_response(200); self.end_headers()
                self.wfile.write(str(Handler.destinations).encode())
            else:
                Handler.destinations += 1
                self.send_response(200); self.end_headers()
                self.wfile.write(b"unexpected")
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_port, flush=True)
    server.serve_forever()
    """#
}
