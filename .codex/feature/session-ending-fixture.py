"""Delayed local hosts for the session ending simulator audit. No real sessions."""
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[1] / "evidence/session-ending"
ROOT.mkdir(parents=True, exist_ok=True)
NOW = time.time() * 1000
LOCK = threading.Lock()
CLOSED = set()
ATTEMPTS = {}
IDS = {name: f"c105e000-0000-4000-8000-{index:012d}" for index, name in enumerate(
    ("Swipe End", "Full Swipe End", "Options End", "Failure Retry", "Hide Directory", "External Session"), 1)}


def sessions():
    return [dict(sessionId=sid, title=name, agent="codex", pid=100 + index,
                 cwd=f"/tmp/lfg-ending/{'hide-me' if name == 'Hide Directory' else 'sessions'}",
                 project="Session ending", model="gpt-6.1-sol", busy=True, status="ok",
                 startedAt=NOW - 120000, lastActivityAt=NOW - index * 1000,
                 control="external" if name == "External Session" else "managed")
            for index, (name, sid) in enumerate(IDS.items()) if sid not in CLOSED]


def log(event):
    with LOCK, (ROOT / "requests.jsonl").open("a") as file:
        file.write(json.dumps({"time": time.time(), **event}) + "\n")


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def respond(self, payload, status=200):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        primary = self.server.server_port == 18941
        if path == "/api/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            try:
                while True:
                    self.wfile.write(b": heartbeat\n\n")
                    self.wfile.flush()
                    time.sleep(1)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == "/api/info":
            payload = {"hostId": "session-ui-pro" if primary else "session-ui-air", "hostName": "Ending fixture"}
        elif path == "/api/ping":
            payload = {"ok": True, "seq": 0, "ts": time.time() * 1000}
        elif path == "/api/sessions":
            payload = {"sessions": sessions() if primary else []}
        elif path in ("/api/sessions/resumable", "/api/sessions/search"):
            payload = {"sessions": [], "total": 0}
        elif path.endswith("/messages"):
            payload = {"messages": [{"id": "fixture-message", "role": "assistant", "kind": "text",
                                     "text": "This local session takes six seconds to end. No real agent is running.", "ts": NOW}]}
        elif path.endswith("/queue"):
            payload = {"queue": []}
        elif path.endswith("/subagents"):
            payload = {"agents": [], "subagents": []}
        elif path == "/api/models":
            payload = {"claude": [], "codex": []}
        elif path == "/api/browser-sign-in/requests":
            payload = {"requests": []}
        elif path == "/api/scheduled-tasks":
            payload = {"tasks": []}
        else:
            payload = {}
        self.respond(payload)

    def do_POST(self):
        path = urlparse(self.path).path
        if path == "/fixture/reset":
            CLOSED.clear()
            ATTEMPTS.clear()
            self.respond({"ok": True})
            return
        if path.endswith("/close"):
            sid = path.split("/")[-2]
            ATTEMPTS[sid] = ATTEMPTS.get(sid, 0) + 1
            attempt = ATTEMPTS[sid]
            log({"event": "close-start", "session": sid, "attempt": attempt})
            time.sleep(6)
            failed = sid == IDS["Failure Retry"] and attempt == 1
            if not failed:
                CLOSED.add(sid)
            log({"event": "close-result", "session": sid, "attempt": attempt, "succeeded": not failed})
            self.respond({"error": "Fixture host could not close the session"} if failed else {"ok": True}, 502 if failed else 200)
            return
        self.respond({"ok": True})


if __name__ == "__main__":
    for port in (18941, 18942):
        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print("Delayed local hosts on 18941 and 18942", flush=True)
    threading.Event().wait()
