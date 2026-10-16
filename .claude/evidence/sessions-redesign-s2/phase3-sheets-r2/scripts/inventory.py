# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Element inventory in sheet-relative laid-out points, for a board render and an app frame.

Ink = pixel farther than TOL from every background colour (sheet / card surfaces).
Rows with ink inside an x-band form y-runs; each y-run is split into elements on x-gaps
>= GAP pt. Prints x0,y0,x1,y1,w,h in sheet pt (app values already divided by s).

usage: inventory.py <img> <kind:app|board> <sheet_top_pt_board> <x0_pt> <x1_pt> [y0_pt] [y1_pt] [gap_pt] [tol] [bgs]
  for app, geometry comes from geom.json (L, T, s); pass the frame name as <img> stem.
  bgs: semicolon list of r,g,b (default sheet+card colours)
"""
import sys, os, json
import numpy as np
from PIL import Image

E = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
img, kind, btop = sys.argv[1], sys.argv[2], float(sys.argv[3])
x0p, x1p = float(sys.argv[4]), float(sys.argv[5])
y0p = float(sys.argv[6]) if len(sys.argv) > 6 else 0
y1p = float(sys.argv[7]) if len(sys.argv) > 7 else 700
gap = float(sys.argv[8]) if len(sys.argv) > 8 else 8
tol = int(sys.argv[9]) if len(sys.argv) > 9 else 10
bgs = sys.argv[10] if len(sys.argv) > 10 else "26,26,28;28,28,30;42,42,45;44,44,46"
BG = [np.array(list(map(int, c.split(",")))) for c in bgs.split(";")]

if kind == "app":
    g = json.load(open(os.path.join(E, "scripts", "geom.json")))[img]
    a = np.asarray(Image.open(os.path.join(E, "app", f"{img}.png")).convert("RGB")).astype(int)
    L, T, s = g["L"], g["T"], g["s"]
    to_px_x = lambda p: L + p * 3 * s
    to_px_y = lambda p: T + p * 3 * s
    to_pt_x = lambda px: (px - L) / 3 / s
    to_pt_y = lambda py: (py - T) / 3 / s
else:
    a = np.asarray(Image.open(os.path.join(E, "board", img)).convert("RGB")).astype(int)
    to_px_x = lambda p: p * 3
    to_px_y = lambda p: (p + btop) * 3
    to_pt_x = lambda px: px / 3
    to_pt_y = lambda py: py / 3 - btop

X0, X1 = int(round(to_px_x(x0p))), int(round(to_px_x(x1p)))
Y0, Y1 = int(round(to_px_y(y0p))), min(a.shape[0], int(round(to_px_y(y1p))))
reg = a[Y0:Y1, X0:X1]
ink = np.ones(reg.shape[:2], bool)
for b in BG:
    ink &= np.abs(reg - b).max(axis=2) > tol


def runs(v, mingap=1):
    out, st, last = [], None, None
    for i, on in enumerate(v):
        if on:
            if st is None:
                st = i
            elif i - last > mingap:
                out.append((st, last)); st = i
            last = i
    if st is not None:
        out.append((st, last))
    return out


gpx = max(1, int(round(gap * 3)))
for ys, ye in runs(ink.any(axis=1)):
    sub = ink[ys:ye + 1]
    for xs, xe in runs(sub.any(axis=0), gpx):
        el = sub[:, xs:xe + 1]
        yy = np.where(el.any(axis=1))[0]
        px0, px1 = X0 + xs, X0 + xe + 1
        py0, py1 = Y0 + ys + yy.min(), Y0 + ys + yy.max() + 1
        col = reg[ys + yy.min():ys + yy.max() + 1, xs:xe + 1][el[yy.min():yy.max() + 1]]
        mx = col[np.argmax(col.sum(axis=1))]
        print(f"x {to_pt_x(px0):7.2f}-{to_pt_x(px1):7.2f}  y {to_pt_y(py0):7.2f}-{to_pt_y(py1):7.2f}  w {to_pt_x(px1)-to_pt_x(px0):6.2f} h {to_pt_y(py1)-to_pt_y(py0):6.2f}  brightest {mx.tolist()}")
