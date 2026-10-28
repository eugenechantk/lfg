"""Before/after protocol for one installed build. Same steps, same order, every run.

Usage: ab.py --sim <udid> --label <before|after>

With the live fixture streaming (rate.txt "4 20"):
  1. list-idle:   10 s on the list top, working rows on screen, no input
  2. list-scroll: 8 swipes (4 down the list, 4 back), 20 s window
  3. open a working session by deep link
  4. detail-idle: 10 s in the open session, no input
  5. detail-scroll: 8 swipes into history and back, 20 s window
Each window records process CPU, main-thread busy share (macOS `sample`), and
the wall time of every swipe command (a starved main thread answers the
automation late, so this is a direct responsiveness signal).
"""
import argparse
import json
import subprocess
import time
from pathlib import Path

import measure

HERE = Path(__file__).resolve().parent
SWIPE_TIMEOUT = 60


def flowdeck(*args, timeout=SWIPE_TIMEOUT, check=True):
    started = time.monotonic()
    try:
        subprocess.run(["flowdeck", *args], text=True, capture_output=True, timeout=timeout, check=check)
        ok = True
    except subprocess.TimeoutExpired:
        ok = False
    return ok, round(time.monotonic() - started, 2)


def window(sim, pid, root, name, seconds, swipes):
    out = root / name
    out.mkdir(parents=True, exist_ok=True)
    start_cpu, started = measure.cpu_seconds(pid), time.monotonic()
    sampler = subprocess.Popen(["/usr/bin/sample", str(pid), str(seconds), "1", "-file", str(out / "stacks.txt")],
                               stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    time.sleep(0.5)
    gestures = []
    for direction in swipes:
        ys = ("250", "650") if direction == "down" else ("650", "250")
        ok, secs = flowdeck("ui", "simulator", "swipe", direction, "-S", sim, "--duration", "0.3",
                            "--distance", "0.5", "--from", f"200,{ys[0]}", "--to", f"200,{ys[1]}", "--json")
        gestures.append(dict(direction=direction, ok=ok, seconds=secs))
        time.sleep(0.6)
    remaining = seconds - (time.monotonic() - started)
    if remaining > 0:
        time.sleep(remaining)
    sampler.wait(timeout=180)
    elapsed = time.monotonic() - started
    cpu = measure.cpu_seconds(pid) - start_cpu
    stacks = measure.summarize(out / "stacks.txt")
    busy_share = stacks["main_busy"] / max(1, stacks["main_samples"])
    row = dict(window=name, elapsed=round(elapsed, 1), cpu_seconds=round(cpu, 2),
               cpu_percent=round(100 * cpu / elapsed, 1), main_busy_percent=round(100 * busy_share, 1),
               swipe_seconds=[g["seconds"] for g in gestures], swipe_timeouts=sum(not g["ok"] for g in gestures),
               stacks=stacks)
    (out / "metrics.json").write_text(json.dumps(row, indent=2))
    print(json.dumps({k: v for k, v in row.items() if k != "stacks"}), flush=True)
    return row


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--sim", required=True)
    p.add_argument("--label", required=True)
    p.add_argument("--session", default="live-pro-3")
    p.add_argument("--part", choices=["all", "detail"], default="all")
    args = p.parse_args()
    root = HERE / "ab" / args.label
    root.mkdir(parents=True, exist_ok=True)
    pid = measure.find_pid(args.sim)
    rows = []
    if args.part == "all":
        rows += [window(args.sim, pid, root, "1-list-idle", 10, []),
                 window(args.sim, pid, root, "2-list-scroll", 20, ["up"] * 4 + ["down"] * 4)]
    flowdeck("ui", "simulator", "open-url", f"lfg://session/{args.session}", "-S", args.sim, "--json")
    time.sleep(1.5)
    # The system "Open in lfg?" sheet appears only sometimes; tap it when present.
    flowdeck("ui", "simulator", "tap", "Open", "-S", args.sim, "--json", timeout=120, check=False)
    time.sleep(4)
    flowdeck("ui", "simulator", "screen", "-S", args.sim, "--output", str(root / "detail.png"), "--json", timeout=120)
    rows.append(window(args.sim, pid, root, "4-detail-idle", 10, []))
    rows.append(window(args.sim, pid, root, "5-detail-scroll", 20, ["down"] * 4 + ["up"] * 4))
    rows = [json.loads((root / name / "metrics.json").read_text())
            for name in ("1-list-idle", "2-list-scroll", "4-detail-idle", "5-detail-scroll")
            if (root / name / "metrics.json").exists()]
    (root / "summary.json").write_text(json.dumps(
        [{k: v for k, v in r.items() if k != "stacks"} for r in rows], indent=2))


if __name__ == "__main__":
    main()
