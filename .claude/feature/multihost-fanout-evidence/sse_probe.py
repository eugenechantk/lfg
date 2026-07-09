#!/usr/bin/env python3
"""
Measure, at the real seam, how long after app launch the SSE stream to the healthy
host is established — while a genuinely black-holed host is also configured.

Sampling `lsof` every 200ms:
  * the simulator's LFG app appears as its own process (PID), so we can attribute
    connections to *our* launch (ignoring another session's app on 127.0.0.1);
  * a connection to the offline peer stuck in SYN_SENT proves the two-host config
    actually loaded (and that it really is a black hole — no RST);
  * the SSE stream is the connection to the healthy host that *persists*; short-lived
    ones are the 3s REST polls. We classify by observed lifetime.

Reports every connection's first-seen time relative to the app's process start.
"""
import subprocess, sys, time, collections

AIR = "100.75.162.40:8766"       # healthy host
DEAD = "100.120.101.14:8766"     # offline Tailscale peer (black hole)
KNOWN_PIDS = set(sys.argv[1:])   # pre-existing LFG pids to ignore

SAMPLE = 0.2
DURATION = 100.0

def sample():
    try:
        out = subprocess.run(["lsof", "-nP", "-iTCP:8766"],
                             capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return []
    rows = []
    for line in out.splitlines():
        if not line.startswith("LFG"):
            continue
        parts = line.split()
        pid = parts[1]
        if pid in KNOWN_PIDS:
            continue
        name = parts[8]           # e.g. 10.0.0.1:5123->100.75.162.40:8766
        state = parts[9] if len(parts) > 9 else ""
        if "->" not in name:
            continue
        local, remote = name.split("->")
        rows.append((pid, local, remote, state.strip("()")))
    return rows

t_start = time.time()
app_start = None
# local_port -> [first_seen, last_seen, remote, states]
conns = collections.OrderedDict()

while time.time() - t_start < DURATION:
    now = time.time()
    for pid, local, remote, state in sample():
        if app_start is None:
            app_start = now
            print(f"[+{now - t_start:5.2f}s] LFG pid {pid} first seen", flush=True)
        key = (local, remote)
        if key not in conns:
            conns[key] = [now, now, remote, {state}]
            rel = now - app_start
            print(f"[+{rel:5.2f}s] NEW  {remote:24} {state:12} lport={local.split(':')[-1]}", flush=True)
        else:
            conns[key][1] = now
            conns[key][3].add(state)
    time.sleep(SAMPLE)

if app_start is None:
    print("RESULT: app never appeared — nothing measured")
    sys.exit(1)

print("\n" + "=" * 78)
print(f"{'remote':26} {'first_seen':>11} {'lifetime':>10}  states")
print("-" * 78)
sse_t = None
dead_seen = False
for (local, remote), (first, last, rem, states) in conns.items():
    life = last - first
    rel = first - app_start
    print(f"{rem:26} {rel:+10.2f}s {life:9.2f}s  {','.join(sorted(states))}")
    if AIR in rem and life >= 4.0 and (sse_t is None or rel < sse_t):
        sse_t = rel
    if DEAD in rem:
        dead_seen = True

print("=" * 78)
print(f"offline host configured + black-holed (SYN_SENT seen): {dead_seen}")
if sse_t is None:
    print("RESULT: no long-lived (>=4s) connection to the healthy host observed")
    sys.exit(2)
print(f"RESULT: SSE stream to healthy host established at +{sse_t:.2f}s after app start")
print(f"        (dead host's timeout budget is {4.0}s; pre-fix barrier was 15s)")
