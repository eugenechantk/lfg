"""Record and sample one repeatable scroll window using FlowDeck gestures."""
import argparse
import json
import shutil
import subprocess
import time
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--sim", required=True)
parser.add_argument("--pid", required=True, type=int)
parser.add_argument("--label", required=True)
parser.add_argument("--surface", choices=["sessions", "tasks", "transcript"], required=True)
parser.add_argument("--session-dir", required=True, type=Path)
parser.add_argument("--ipad", action="store_true")
args = parser.parse_args()
root = Path(__file__).resolve().parent / args.label
root.mkdir(exist_ok=True)


def cpu():
    value = subprocess.check_output(["ps", "-p", str(args.pid), "-o", "time="], text=True).strip()
    parts = [float(x) for x in value.split(":")]
    return sum(x*60**i for i, x in enumerate(reversed(parts)))


start_cpu = cpu()
started = time.monotonic()
sample = subprocess.Popen(["/usr/bin/sample", str(args.pid), "20", "1", "-file", str(root/"stacks.txt")],
                          stdout=(root/"sample.log").open("w"), stderr=subprocess.STDOUT)
video = subprocess.Popen(["flowdeck", "ui", "simulator", "record", "-S", args.sim,
                          "--duration", "22", "--output", str(root/"scroll.mov"), "--json"],
                         stdout=(root/"record.json").open("w"), stderr=subprocess.STDOUT)
time.sleep(1)
forward = "down" if args.surface == "transcript" else "up"
directions = [forward]*4 + [("up" if forward == "down" else "down")]*4
events = []
for index, direction in enumerate(directions):
    command = ["flowdeck", "ui", "simulator", "swipe", direction, "-S", args.sim,
               "--duration", "0.3", "--distance", "0.55", "--json"]
    x = ("580" if args.surface == "transcript" else "160") if args.ipad else "180"
    ys = (("300", "800") if direction == "down" else ("800", "300")) if args.ipad else (("160", "510") if direction == "down" else ("510", "160"))
    command += ["--from", f"{x},{ys[0]}", "--to", f"{x},{ys[1]}"]
    before = time.time()*1000
    result = subprocess.run(command, text=True, capture_output=True, timeout=15)
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout)
    time.sleep(0.5)
    deadline = time.monotonic()+4
    while (args.session_dir/"latest.jpg").stat().st_mtime*1000 < before and time.monotonic() < deadline:
        time.sleep(0.2)
    meta = {"timestampMs": (args.session_dir/"latest.jpg").stat().st_mtime*1000}
    if meta["timestampMs"] < before:
        subprocess.run(["flowdeck", "ui", "simulator", "screen", "-S", args.sim,
                        "--output", str(root/f"gesture-{index:02d}.jpg"), "--json"], check=True,
                       stdout=subprocess.DEVNULL)
    else:
        shutil.copyfile(args.session_dir/"latest.jpg", root/f"gesture-{index:02d}.jpg")
    tree = json.loads((args.session_dir/"latest-tree.json").read_text())
    if not tree:
        raise RuntimeError("Empty accessibility viewport")
    (root/f"gesture-{index:02d}.json").write_text(json.dumps(tree))
    events.append(dict(direction=direction, elapsed=time.monotonic()-started, timestamp=meta["timestampMs"]))
    print(f"{args.label}: gesture {index+1}/8 captured", flush=True)
remaining = 20-(time.monotonic()-started)
if remaining > 0:
    time.sleep(remaining)
end_cpu = cpu()
elapsed = time.monotonic()-started
sample.wait(timeout=60)
video.wait(timeout=40)
metrics = dict(sim=args.sim, pid=args.pid, surface=args.surface, cpu_seconds=end_cpu-start_cpu,
               elapsed_seconds=elapsed, cpu_percent=100*(end_cpu-start_cpu)/elapsed,
               sample_exit=sample.returncode, record_exit=video.returncode, gestures=events)
(root/"metrics.json").write_text(json.dumps(metrics, indent=2))
print(json.dumps(metrics), flush=True)
