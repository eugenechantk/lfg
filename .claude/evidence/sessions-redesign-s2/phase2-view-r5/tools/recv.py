# Tiny receiver: POST /<name> with a text body -> writes design/<name>.txt. Used for DOM dumps that exceed the JS tool's output limit.
import http.server, os, sys

OUT = "/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r5/design"

class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(n)
        name = os.path.basename(self.path.strip("/")) or "dump"
        with open(os.path.join(OUT, name + ".txt"), "wb") as f:
            f.write(body)
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(b"ok")
        print("wrote", name, n, flush=True)

    def do_OPTIONS(self):
        self.send_response(204)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "*")
        self.send_header("Access-Control-Allow-Methods", "POST")
        self.end_headers()

http.server.HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
