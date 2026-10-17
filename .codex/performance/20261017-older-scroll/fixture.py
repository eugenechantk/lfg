"""Isolated read-only scrolling workload. Never connects to production hosts."""
import json
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

NOW = 1792198800000
PORTS = (19171, 19172)


def sessions(host):
    return [dict(agent="codex", pid=1000+i, cwd=f"/workspace/project-{i % 8}",
                 project=f"Project {i % 8}", title=f"Scroll session {i:03d}: Review implementation and evidence",
                 sessionId=f"scroll-{host}-{i}", busy=False, status="idle", model="gpt-6.1-sol",
                 startedAt=NOW-3600000, lastActivityAt=NOW-i*60000,
                 lastUserText="Review the implementation and verify the result") for i in range(160)]


def tasks(host):
    control = Path(__file__).with_name("fixture-task-suffix.txt")
    suffix = control.read_text() if control.exists() else ""
    result = []
    for i in range(100):
        run = dict(id=f"run-{i}", taskId=f"scroll-task-{host}-{i}", agent="codex", trigger="scheduled",
                   status="succeeded", startedAt=NOW-1800000, finishedAt=NOW-900000,
                   summary="Review complete. All checks passed.")
        result.append(dict(id=f"scroll-task-{host}-{i}", name=f"Scroll task {i:03d}: Check project progress{suffix}",
                           prompt="Review progress and report findings.", cwd=f"/workspace/project-{i % 8}",
                           agent="codex", enabled=True, model="gpt-6.1-sol",
                           schedule=dict(kind="cron", expression=f"{i % 60} 9 * * 1-5", timezone="Asia/Hong_Kong"),
                           nextRunAt=NOW+(i+1)*60000, upcomingRuns=[NOW+(i+1)*60000],
                           lastRun=run, recentRuns=[run], runCount=10, succeededCount=10, consecutiveFailures=0))
    return result


def messages():
    result = []
    for i in range(90):
        result.append(dict(id=f"user-{i}", role="user", kind="text", text=f"Review change {i} and explain the tradeoffs.", ts=NOW+i*10000))
        result.append(dict(id=f"reply-{i}", role="assistant", kind="text", ts=NOW+i*10000+1000,
                           text=f"## Review {i}\n\nThe implementation keeps **stable identity** and uses a bounded workload. "
                           "Scrolling should remain responsive while new rows appear.\n\n"
                           "- Preserve selection and navigation.\n- Reuse expensive presentation work.\n- Verify the complete interaction.\n\n"
                           "```swift\nlet visible = records.filter { $0.isVisible }\nfor record in visible {\n    render(record)\n}\n```\n\n"
                           "| Check | Result |\n| --- | --- |\n| Ordering | Preserved |\n| Selection | Native |\n\n"
                           "A [reference](https://developer.apple.com) supports the final review. "
                           "The next step checks the result with repeated forward and reverse scrolling."))
    return result


MESSAGES = messages()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *_):
        pass

    def do_GET(self):
        host = "pro" if self.server.server_port == PORTS[0] else "air"
        path = urlparse(self.path).path
        if path == "/api/events":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            try:
                while True:
                    self.wfile.write(b": heartbeat\n\n")
                    self.wfile.flush()
                    time.sleep(2)
            except (BrokenPipeError, ConnectionResetError):
                pass
            return
        if path == "/api/info": payload = dict(hostId=f"session-ui-{host}", hostName=f"Fixture {host}")
        elif path == "/api/ping": payload = dict(ok=True, seq=0, ts=time.time()*1000)
        elif path == "/api/sessions": payload = dict(sessions=sessions(host))
        elif path in ("/api/sessions/resumable", "/api/sessions/search"): payload = dict(sessions=[], total=0)
        elif path == "/api/scheduled-tasks": payload = dict(tasks=tasks(host))
        elif path.startswith("/api/scheduled-tasks/") and path.endswith("/runs"):
            task_id = path.split("/")[-2]
            record = next((task for task in tasks(host) if task["id"] == task_id), None)
            runs = record["recentRuns"] if record else []
            payload = dict(runs=runs, total=len(runs))
        elif path.endswith("/messages"): payload = dict(messages=MESSAGES, hasMore=False)
        elif path.endswith("/queue"): payload = dict(queue=[])
        elif path.endswith("/subagents"): payload = dict(agents=[], subagents=[])
        elif path == "/api/dirs": payload = dict(dirs=[], inbox=None)
        elif path == "/api/repos": payload = dict(repos=[])
        elif path == "/api/users": payload = dict(users=[])
        elif path == "/api/browser-sign-in/requests": payload = dict(requests=[])
        elif path == "/api/models": payload = dict(claude=[], codex=[])
        else: payload = {}
        body = json.dumps(payload).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')


if __name__ == "__main__":
    for port in PORTS:
        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"Scroll fixtures listening on {PORTS}", flush=True)
    threading.Event().wait()
