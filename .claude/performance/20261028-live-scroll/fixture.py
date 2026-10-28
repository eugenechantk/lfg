"""Live-session scrolling workload. Read-only, local, never touches real hosts.

Two fake hosts with 160 sessions each. Per host: 24 working sessions that stream
`msg` events, 20 sessions that turn unread, the rest idle. The `/api/events`
stream replays a backlog (catch-up after foregrounding), then emits live events
at a steady rate with periodic bursts, the shape seen in the real journal
(peaks of 3-15 events/s, bursts of busy flips across many sessions).

Control file `rate.txt` beside this script: "<msgs/s per host> <burst every N s>".
"0 0" turns the live stream off (heartbeats only) for an idle baseline.
"""
import json
import random
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

PORTS = (19181, 19182)
HERE = Path(__file__).resolve().parent
SESSIONS_PER_HOST = 160
WORKING = 24
UNREAD = 20
BACKLOG = 600          # events replayed per host on a fresh cursor
START_MS = time.time() * 1000


def now_ms():
    return time.time() * 1000


def idle_ids():
    """Control file `idle.txt`: session ids (one per line) to show as idle."""
    try:
        return {line.strip() for line in (HERE / "idle.txt").read_text().splitlines() if line.strip()}
    except Exception:
        return set()


def rate():
    try:
        parts = (HERE / "rate.txt").read_text().split()
        return float(parts[0]), float(parts[1])
    except Exception:
        return 4.0, 20.0


def sid(host, i):
    return f"live-{host}-{i}"


def is_working(i):
    return i < WORKING


def is_unread(i):
    return WORKING <= i < WORKING + UNREAD


def message(host, i, n, role="assistant"):
    text = (f"Step {n}: checked the change in `src/module_{i % 9}.ts` and ran the focused suite. "
            "All 42 tests pass. Next I will verify the list ordering and the selection state.")
    if role == "user":
        text = f"Please continue with step {n} and report back."
    return dict(id=f"m-{host}-{i}-{n}", role=role, kind="text", text=text, ts=now_ms())


def session(host, i):
    working = is_working(i) and sid(host, i) not in idle_ids()
    minute = int(now_ms() // 60000)
    # Unread rows: the newest message id changes every minute, so after the
    # first poll the client sees a message it has not read.
    last_id = f"last-{host}-{i}-{minute}" if is_unread(i) else f"last-{host}-{i}"
    return dict(
        agent="claude" if i % 3 else "codex", pid=2000 + i, cwd=f"/workspace/project-{i % 8}",
        project=f"Project {i % 8}", sessionId=sid(host, i),
        title=f"Live session {i:03d}: Review implementation and evidence",
        busy=working, status="ok", model="claude-opus-5" if i % 3 else "gpt-6.1-sol",
        startedAt=START_MS - 3_600_000, lastActivityAt=now_ms() - (0 if working else i * 60_000),
        lastUserAt=START_MS - 120_000 if working else START_MS - 3_600_000,
        lastUserText="Review the implementation and verify the result",
        runningChildAgentCount=0, runningBackgroundProcessCount=0, childAgents=[],
        last=dict(id=last_id, role="assistant", kind="text", text="Done.", ts=now_ms()),
    )


def history():
    result = []
    for i in range(90):
        result.append(dict(id=f"user-{i}", role="user", kind="text",
                           text=f"Review change {i} and explain the tradeoffs.", ts=START_MS + i * 10000))
        result.append(dict(id=f"reply-{i}", role="assistant", kind="text", ts=START_MS + i * 10000 + 1000,
                           text=f"## Review {i}\n\nThe implementation keeps **stable identity** and uses a bounded workload. "
                           "Scrolling should remain responsive while new rows appear.\n\n"
                           "- Preserve selection and navigation.\n- Reuse expensive presentation work.\n- Verify the complete interaction.\n\n"
                           "```swift\nlet visible = records.filter { $0.isVisible }\nfor record in visible {\n    render(record)\n}\n```\n\n"
                           "| Check | Result |\n| --- | --- |\n| Ordering | Preserved |\n| Selection | Native |\n\n"
                           "A [reference](https://developer.apple.com) supports the final review."))
    return result


HISTORY = history()


class Journal:
    """One append-only event log per host, so a reconnect resumes losslessly."""

    def __init__(self, host):
        self.host = host
        self.events = []      # (seq, event, data)
        self.lock = threading.Condition()
        self.counter = 0
        for _ in range(BACKLOG):
            self._make_msg()

    def _append(self, event, data):
        with self.lock:
            seq = len(self.events) + 1
            self.events.append((seq, event, json.dumps(data)))
            self.lock.notify_all()

    def _make_msg(self):
        self.counter += 1
        i = random.randrange(WORKING)
        if sid(self.host, i) in idle_ids():
            return
        self._append("msg", dict(sid=sid(self.host, i), m=message(self.host, i, self.counter)))

    def run(self):
        last_burst = time.monotonic()
        idle_now = set()
        while True:
            wanted = {x for x in idle_ids() if x.startswith(f"live-{self.host}-")}
            for x in sorted(wanted - idle_now):
                self._append("busy", dict(sid=x, busy=False))
            for x in sorted(idle_now - wanted):
                self._append("busy", dict(sid=x, busy=True))
            idle_now = wanted
            per_sec, burst_every = rate()
            if per_sec <= 0:
                time.sleep(0.5)
                continue
            time.sleep(1.0 / per_sec)
            self._make_msg()
            if burst_every > 0 and time.monotonic() - last_burst > burst_every:
                last_burst = time.monotonic()
                # A burst of busy flips (turns ending and restarting) across
                # every working session, then a quick run of messages.
                busy_ids = [sid(self.host, i) for i in range(WORKING) if sid(self.host, i) not in idle_ids()]
                for x in busy_ids:
                    self._append("busy", dict(sid=x, busy=False))
                for x in busy_ids:
                    self._append("busy", dict(sid=x, busy=True))
                for _ in range(30):
                    self._make_msg()


JOURNALS = {}
STATS = {}
STATS_LOCK = threading.Lock()


def count(key):
    with STATS_LOCK:
        STATS[key] = STATS.get(key, 0) + 1


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def _host(self):
        return "pro" if self.server.server_port == PORTS[0] else "air"

    def _events(self, since):
        journal = JOURNALS[self._host()]
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        cursor = since
        last_hb = 0.0
        try:
            with journal.lock:
                head = len(journal.events)
            if cursor > head:
                self.wfile.write(f"event: resync\ndata: {json.dumps(dict(head=head))}\n\n".encode())
                self.wfile.flush()
                cursor = head
            while True:
                with journal.lock:
                    pending = journal.events[cursor:]
                    if not pending:
                        journal.lock.wait(timeout=1.0)
                        pending = journal.events[cursor:]
                chunks = []
                for seq, event, data in pending:
                    chunks.append(f"id: {seq}\nevent: {event}\ndata: {data}\n\n")
                    cursor = seq
                if chunks:
                    self.wfile.write("".join(chunks).encode())
                    self.wfile.flush()
                if time.monotonic() - last_hb > 2:
                    last_hb = time.monotonic()
                    self.wfile.write(f": hb {len(journal.events)}\n\n".encode())
                    self.wfile.flush()
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        host = self._host()
        parsed = urlparse(self.path)
        path = parsed.path
        count(f"{host} GET {re.sub(r'/sessions/[^/]+/', '/sessions/:id/', path)}")
        if path == "/__stats":
            body = json.dumps(STATS, indent=1, sort_keys=True).encode()
            self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers()
            self.wfile.write(body); return
        if path == "/api/events":
            since = int((parse_qs(parsed.query).get("since") or ["0"])[0] or 0)
            return self._events(max(0, since))
        if path == "/api/info": payload = dict(hostId=f"session-ui-{host}", hostName=f"Fixture {host}")
        elif path == "/api/ping": payload = dict(ok=True, seq=len(JOURNALS[host].events), ts=now_ms())
        elif path == "/api/sessions":
            payload = dict(sessions=[session(host, i) for i in range(SESSIONS_PER_HOST)])
        elif path in ("/api/sessions/resumable", "/api/sessions/search"): payload = dict(sessions=[], total=0)
        elif path == "/api/scheduled-tasks": payload = dict(tasks=[])
        elif path.endswith("/messages"): payload = dict(messages=HISTORY, hasMore=False)
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
        count(f"{self._host()} POST {re.sub(r'/sessions/[^/]+/', '/sessions/:id/', urlparse(self.path).path)}")
        self.rfile.read(int(self.headers.get("Content-Length", 0) or 0))
        body = b'{"ok":true}'
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


if __name__ == "__main__":
    random.seed(7)
    for port, host in zip(PORTS, ("pro", "air")):
        JOURNALS[host] = Journal(host)
        threading.Thread(target=JOURNALS[host].run, daemon=True).start()
        server = ThreadingHTTPServer(("127.0.0.1", port), Handler)
        server.daemon_threads = True
        threading.Thread(target=server.serve_forever, daemon=True).start()
    print(f"Live scroll fixtures listening on {PORTS}", flush=True)
    threading.Event().wait()
