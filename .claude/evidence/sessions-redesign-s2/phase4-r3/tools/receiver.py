"""Loopback-only POST sink: writes the request body to <outdir>/<path-basename>. Used to pull DOM dumps out of the board tab."""
import os
import sys
from http.server import BaseHTTPRequestHandler, HTTPServer

OUT = sys.argv[2]


class H(BaseHTTPRequestHandler):
    def do_POST(self):
        name = os.path.basename(self.path.split("?")[0]) or "dump.txt"
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        with open(os.path.join(OUT, name), "wb") as f:
            f.write(body)
        print("wrote", name, len(body), flush=True)
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()


HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
