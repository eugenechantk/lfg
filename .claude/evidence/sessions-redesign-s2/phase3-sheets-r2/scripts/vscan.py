# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Vertical (or horizontal) colour-transition scan at a sheet-pt coordinate, output in sheet pt.
usage: vscan.py <img> <app|board> <board_sheet_top_pt> <v|h> <coord_pt> [from_pt] [to_pt] [thr]
  v: scan down the column at x=coord; h: scan along the row at y=coord."""
import sys, os, json
import numpy as np
from PIL import Image

E = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
img, kind, btop, mode, c = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4], float(sys.argv[5])
f = float(sys.argv[6]) if len(sys.argv) > 6 else -50
t = float(sys.argv[7]) if len(sys.argv) > 7 else 760
thr = int(sys.argv[8]) if len(sys.argv) > 8 else 5
if kind == "app":
    g = json.load(open(os.path.join(E, "scripts", "geom.json")))[img]
    a = np.asarray(Image.open(os.path.join(E, "app", f"{img}.png")).convert("RGB")).astype(int)
    L, T, s = g["L"], g["T"], g["s"]
    px = lambda p, ax: (L if ax == "x" else T) + p * 3 * s
    pt = lambda q, ax: (q - (L if ax == "x" else T)) / 3 / s
else:
    a = np.asarray(Image.open(os.path.join(E, "board", img)).convert("RGB")).astype(int)
    px = lambda p, ax: p * 3 if ax == "x" else (p + btop) * 3
    pt = lambda q, ax: q / 3 if ax == "x" else q / 3 - btop
if mode == "v":
    x = int(round(px(c, "x")))
    lo, hi = max(0, int(px(f, "y"))), min(a.shape[0] - 1, int(px(t, "y")))
    line = a[lo:hi, x]; ax = "y"
else:
    y = int(round(px(c, "y")))
    lo, hi = max(0, int(px(f, "x"))), min(a.shape[1] - 1, int(px(t, "x")))
    line = a[y, lo:hi]; ax = "x"
prev = line[0]
for i in range(1, len(line)):
    if np.abs(line[i] - prev).max() > thr:
        print(f"{pt(lo + i, ax):8.2f}  {prev.tolist()} -> {line[i].tolist()}")
    prev = line[i]
