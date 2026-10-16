#!/usr/bin/env python3
"""Loopback receiver: POST /<name> writes the body to ../<name>. Port 8797, 127.0.0.1 only."""
import http.server, os, sys

OUT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

class H(http.server.BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "*")

    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()

    def do_POST(self):
        name = os.path.basename(self.path.strip("/")) or "dump.txt"
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(body)
        self.send_response(200); self._cors(); self.end_headers()
        self.wfile.write(b"ok %d" % len(body))
        print("wrote", name, len(body), flush=True)

http.server.HTTPServer(("127.0.0.1", 8797), H).serve_forever()
