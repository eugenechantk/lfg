"""Independent bounded xctrace capture, using only FlowDeck for UI gestures."""
import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--sim", required=True)
parser.add_argument("--pid", required=True)
parser.add_argument("--label", required=True)
parser.add_argument("--surface", required=True, choices=["tasks", "transcript"])
parser.add_argument("--session-dir", required=True, type=Path)
parser.add_argument("--host", action="store_true")
parser.add_argument("--template", default="Time Profiler")
args = parser.parse_args()
root = Path(__file__).resolve().parent / "traces" / args.label
root.mkdir(parents=True, exist_ok=True)
xctrace = "/Applications/Xcode.app/Contents/Developer/usr/bin/xctrace"
command = [xctrace, "record", "--template", args.template,
           "--attach", args.pid, "--time-limit", "22s", "--output", str(root / "scroll.trace"),
           "--no-prompt"]
if args.template == "Time Profiler":
    command += ["--instrument", "Hangs"]
if not args.host:
    command += ["--device", args.sim]
(root / "command.json").write_text(json.dumps(command, indent=2))
with (root / "record.log").open("w") as log:
    process = subprocess.Popen(command, stdout=log, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 45
    ready = False
    while time.monotonic() < deadline and process.poll() is None:
        text = (root / "record.log").read_text()
        if "Recording started" in text or "Ctrl-C to stop the recording" in text:
            ready = True
            break
        time.sleep(0.5)
    if not ready:
        if process.poll() is None:
            process.terminate()
            process.wait(timeout=15)
        (root / "result.json").write_text(json.dumps(dict(ready=False, exit=process.returncode), indent=2))
        raise SystemExit((root / "record.log").read_text())
    start = time.monotonic()
    forward = "down" if args.surface == "transcript" else "up"
    directions = [forward] * 4 + [("up" if forward == "down" else "down")] * 4
    events = []
    for index, direction in enumerate(directions):
        x = "580" if args.surface == "transcript" else "160"
        ys = ("300", "800") if direction == "down" else ("800", "300")
        gesture = ["flowdeck", "ui", "simulator", "swipe", direction, "-S", args.sim,
                   "--duration", "0.3", "--distance", "0.55", "--json",
                   "--from", f"{x},{ys[0]}", "--to", f"{x},{ys[1]}"]
        subprocess.run(gesture, text=True, capture_output=True, timeout=15, check=True)
        time.sleep(0.5)
        shutil.copyfile(args.session_dir / "latest.jpg", root / f"gesture-{index:02d}.jpg")
        events.append(dict(direction=direction, elapsed=time.monotonic()-start))
        print(f"{args.label}: gesture {index+1}/8", flush=True)
    process.wait(timeout=45)
result = dict(ready=True, exit=process.returncode, gestures=events, host=args.host,
              sim=args.sim, pid=args.pid, surface=args.surface, template=args.template)
(root / "result.json").write_text(json.dumps(result, indent=2))
if process.returncode == 0:
    subprocess.run([xctrace, "export", "--input", str(root / "scroll.trace"), "--toc",
                    "--output", str(root / "toc.xml")], check=True)
print(json.dumps(result), flush=True)
