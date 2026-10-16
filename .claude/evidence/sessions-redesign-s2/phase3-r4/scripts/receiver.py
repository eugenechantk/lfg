#!/usr/bin/env python3
"""Loopback receiver: POST /save?name=<file> writes the body into ../board/<file>.
Binary bodies (data URLs decoded by the client) are written as-is."""
import http.server, os, urllib.parse, sys

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "board")


class H(http.server.BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def do_POST(self):
        q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query)
        name = os.path.basename(q.get("name", ["out.txt"])[0])
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(body)
        self.send_response(200); self._cors(); self.end_headers()
        self.wfile.write(f"saved {name} {len(body)}".encode())

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8797
    http.server.HTTPServer(("127.0.0.1", port), H).serve_forever()
