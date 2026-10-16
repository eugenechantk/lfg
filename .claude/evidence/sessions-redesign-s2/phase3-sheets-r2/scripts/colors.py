# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Colour probes in sheet pt.
  fill:  label:bx,by:ax,ay            -> mean of a 5x5 px patch at each point
  text:  label:bx0,by0,bx1,by1:ax0,ay0,ax1,ay1  (prefix 'T') -> 'core' text colour: mean of the
         pixels whose distance from the region's modal bg is in the top 15% (glyph cores)
usage: colors.py <board_img> <board_top> <app_frame> probe [probe ...]"""
import sys, os, json
import numpy as np
from PIL import Image

E = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
bimg, btop, af = sys.argv[1], float(sys.argv[2]), sys.argv[3]
B = np.asarray(Image.open(os.path.join(E, "board", bimg)).convert("RGB")).astype(float)
g = json.load(open(os.path.join(E, "scripts", "geom.json")))[af]
A = np.asarray(Image.open(os.path.join(E, "app", f"{af}.png")).convert("RGB")).astype(float)
L, T, s = g["L"], g["T"], g["s"]
bp = lambda x, y: (round(x * 3), round((y + btop) * 3))
ap = lambda x, y: (round(L + x * 3 * s), round(T + y * 3 * s))


def patch(img, xy):
    x, y = xy
    return img[y - 2:y + 3, x - 2:x + 3].reshape(-1, 3).mean(axis=0).round().astype(int).tolist()


def core(img, p0, p1):
    reg = img[p0[1]:p1[1], p0[0]:p1[0]].reshape(-1, 3)
    vals, counts = np.unique(reg.astype(int), axis=0, return_counts=True)
    bg = vals[counts.argmax()]
    d = np.abs(reg - bg).max(axis=1)
    sel = reg[d >= 0.8 * d.max()]
    return bg.tolist(), sel.mean(axis=0).round().astype(int).tolist()


for probe in sys.argv[4:]:
    lab, b, a = probe.split(":")
    if lab.startswith("T"):
        bx0, by0, bx1, by1 = map(float, b.split(",")); ax0, ay0, ax1, ay1 = map(float, a.split(","))
        print(f"{lab:22s} board bg/core {core(B, bp(bx0, by0), bp(bx1, by1))}   app bg/core {core(A, ap(ax0, ay0), ap(ax1, ay1))}")
    else:
        bx, by = map(float, b.split(",")); ax, ay = map(float, a.split(","))
        print(f"{lab:22s} board {patch(B, bp(bx, by))}   app {patch(A, ap(ax, ay))}")
