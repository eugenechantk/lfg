"""One repeatable 20 s window: sample the app's main thread while swiping.

Usage: measure.py --sim <udid> --label <name> --surface list|transcript|idle

Writes <label>/stacks.txt (macOS `sample`), <label>/metrics.json, and prints a
summary: process CPU over the window, main-thread busy samples, and inclusive
samples for the view bodies and store paths under suspicion.
"""
import argparse
import json
import re
import subprocess
import time
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
WINDOW = 20

MARKERS = {
    "detail_body": "SessionDetailView.body",
    "detail_any": "SessionDetailView",
    "transcript_row": "TranscriptMessageView",
    "list_sections": "SessionListView.visibleSections",
    "list_view": "SessionListView",
    "session_row_body": "SessionRow.body",
    "status_dot": "SessionRowStatusDot",
    "store_apply": "SessionStore.apply",
    "store_ingest": "SessionStore.ingest",
    "store_rebuild": "SessionStore.rebuildSessions",
    "host_link": "HostLink",
    "group_for": "SessionStore.group(for:",
    "user_defaults": "CFPreferences",
    "attribute_graph": "AG::Graph",
    "core_animation": "CA::",
    "accessibility": "_AXXMIG",
}


def find_pid(sim):
    out = subprocess.check_output(["ps", "-axo", "pid=,command="], text=True)
    for line in out.splitlines():
        if sim in line and "/LFG.app/LFG" in line:
            return int(line.split()[0])
    raise SystemExit(f"no LFG process on {sim}")


def cpu_seconds(pid):
    value = subprocess.check_output(["ps", "-p", str(pid), "-o", "time="], text=True).strip()
    parts = [float(x) for x in value.split(":")]
    return sum(x * 60 ** i for i, x in enumerate(reversed(parts)))


def summarize(path):
    text = path.read_text()
    lines = text.split("Call graph:", 1)[1].splitlines()
    nodes, stack, active = [], [], False
    for line in lines:
        m = re.match(r"^([ +!|:]*)(\d+) (.*)", line)
        if not m:
            continue
        indent, count, name = len(m[1]), int(m[2]), m[3]
        if name.startswith("Thread_"):
            if active:
                break
            if "Main Thread" not in name and "com.apple.main-thread" not in name:
                continue
            active = True
        if not active:
            continue
        while stack and nodes[stack[-1]]["indent"] >= indent:
            stack.pop()
        parent = stack[-1] if stack else None
        nodes.append(dict(indent=indent, count=count, name=name, children=0, parent=parent))
        if parent is not None:
            nodes[parent]["children"] += count
        stack.append(len(nodes) - 1)
    inclusive, waiting, busy = Counter(), 0, 0
    for i, node in enumerate(nodes):
        weight = max(0, node["count"] - node["children"])
        if not weight:
            continue
        chain, cur = [], i
        while cur is not None:
            chain.append(nodes[cur]["name"])
            cur = nodes[cur]["parent"]
        joined = "\n".join(chain)
        if "mach_msg2_trap" in node["name"] or "__psynch_cvwait" in node["name"] or "semaphore_wait" in node["name"]:
            waiting += weight
            continue
        busy += weight
        for label, marker in MARKERS.items():
            if marker in joined:
                inclusive[label] += weight
    return dict(main_samples=nodes[0]["count"] if nodes else 0, main_busy=busy,
                main_waiting=waiting, inclusive=dict(inclusive))


def swipe(sim, direction, surface):
    x = "200"
    ys = ("250", "650") if direction == "down" else ("650", "250")
    subprocess.run(["flowdeck", "ui", "simulator", "swipe", direction, "-S", sim,
                    "--duration", "0.3", "--distance", "0.5", "--json",
                    "--from", f"{x},{ys[0]}", "--to", f"{x},{ys[1]}"],
                   text=True, capture_output=True, timeout=20, check=True)


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sim", required=True)
    p.add_argument("--label", required=True)
    p.add_argument("--surface", choices=["list", "transcript", "idle"], required=True)
    args = p.parse_args()
    root = HERE / args.label
    root.mkdir(exist_ok=True)
    pid = find_pid(args.sim)
    start_cpu, started = cpu_seconds(pid), time.monotonic()
    sampler = subprocess.Popen(["/usr/bin/sample", str(pid), str(WINDOW), "1", "-file", str(root / "stacks.txt")],
                               stdout=(root / "sample.log").open("w"), stderr=subprocess.STDOUT)
    time.sleep(0.5)
    gestures = []
    if args.surface != "idle":
        # The list scrolls toward older rows with an upward swipe; the inverted
        # transcript scrolls toward older messages with a downward one.
        forward = "up" if args.surface == "list" else "down"
        back = "down" if forward == "up" else "up"
        for direction in [forward] * 4 + [back] * 4:
            swipe(args.sim, direction, args.surface)
            gestures.append(dict(direction=direction, t=round(time.monotonic() - started, 2)))
            time.sleep(0.6)
    remaining = WINDOW - (time.monotonic() - started)
    if remaining > 0:
        time.sleep(remaining)
    sampler.wait(timeout=120)
    end_cpu, elapsed = cpu_seconds(pid), time.monotonic() - started
    metrics = dict(label=args.label, surface=args.surface, pid=pid, cpu_seconds=round(end_cpu - start_cpu, 3),
                   elapsed=round(elapsed, 2), gestures=gestures, stacks=summarize(root / "stacks.txt"))
    (root / "metrics.json").write_text(json.dumps(metrics, indent=2))
    print(json.dumps(metrics, indent=1))


if __name__ == "__main__":
    main()
