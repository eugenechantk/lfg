# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Decode every frame of a recording (ffmpeg rawvideo pipe) and report the cursor block's mean
brightness per frame plus frame timestamps. usage: cursor_frames.py <mov> x0 y0 x1 y1 (px)"""
import sys, subprocess, json
import numpy as np

mov = sys.argv[1]
x0, y0, x1, y1 = [int(v) for v in sys.argv[2:6]]
W, H = 1206, 2622
probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "frame=pts_time",
                        "-of", "json", mov], capture_output=True, text=True)
times = [float(f["pts_time"]) for f in json.loads(probe.stdout)["frames"]]
raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", mov, "-f", "rawvideo", "-pix_fmt", "rgb24", "-"],
                     capture_output=True).stdout
n = len(raw) // (W * H * 3)
frames = np.frombuffer(raw[: n * W * H * 3], dtype=np.uint8).reshape(n, H, W, 3)
vals = [frames[i, y0:y1, x0:x1].reshape(-1, 3).mean(axis=0).round(1).tolist() for i in range(n)]
print("frames", n, "times", [round(t, 3) for t in times])
for i, v in enumerate(vals):
    print(i, v)
