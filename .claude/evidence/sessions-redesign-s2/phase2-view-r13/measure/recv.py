#!/usr/bin/env python3
# Loopback receiver: POST /<name> writes the body to OUT/<name>. CORS open for the board origin.
import http.server, os, sys
OUT = sys.argv[1]
class H(http.server.BaseHTTPRequestHandler):
    def _cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
    def do_OPTIONS(self):
        self.send_response(204); self._cors(); self.end_headers()
    def do_POST(self):
        n = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        name = os.path.basename(self.path.strip('/')) or 'out.txt'
        with open(os.path.join(OUT, name), 'wb') as f:
            f.write(body)
        self.send_response(200); self._cors(); self.end_headers(); self.wfile.write(b'ok')
    def do_GET(self):
        body = open('/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r13/measure/dump.js','rb').read()
        self.send_response(200); self._cors(); self.send_header('Content-Type','text/javascript'); self.end_headers(); self.wfile.write(body)
    def log_message(self, *a):
        pass
http.server.HTTPServer(('127.0.0.1', 8798), H).serve_forever()
