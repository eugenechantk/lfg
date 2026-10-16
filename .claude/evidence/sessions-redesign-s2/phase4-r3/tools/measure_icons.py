"""Icon / dot comparison with template matching (replaces the loose-window icon rows in measure-boxes.tsv).

For every <svg> and small dot <span> in board-dom-<state>.tsv:
  board ink bbox in a tight window (DOM rect + pad); template-match that window over the app within +/-3px;
  app ink bbox in the matched window (same size). Report bbox, centroid, size deltas, centre-pixel colours.
"""
import os
import sys

import numpy as np
from PIL import Image

root = sys.argv[1]
os.chdir(root)
sys.path.insert(0, os.path.join(root, "tools"))
from measure_boxes import records, lum, hexc  # noqa: E402

STATES = ["open", "fold-needs", "fold-working", "fold-recent", "fold-all"]


def load(p):
    return np.array(Image.open(p).convert("RGB")).astype(float)


def ink(img, x0, y0, x1, y1, thr):
    reg = img[y0:y1, x0:x1]
    edge = np.concatenate([reg[0], reg[-1], reg[:, 0], reg[:, -1]])
    bg = np.median(edge, axis=0)
    d = np.abs(lum(reg) - lum(bg[None, None, :]))
    m = d > thr
    if not m.any():
        return None
    ys, xs = np.where(m)
    w = d[m]
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1,
            (xs * w).sum() / w.sum() + x0 + 0.5, (ys * w).sum() / w.sum() + y0 + 0.5)


rows = []
for st in STATES:
    B, A = load(f"board-{st}.png"), load(f"app-{st}-srgb.png")
    gB, gA = lum(B), lum(A)
    for f in records(f"board-dom-{st}.tsv"):
        if f[0] != "box":
            continue
        lab = f[1]
        x, y, w, h = map(float, f[2:6])
        is_svg = lab.startswith("svg")
        is_dot = lab.startswith("span") and w <= 12 and h <= 12
        if not (is_svg or is_dot):
            continue
        if is_dot and x < 70 and y < 40:
            continue  # drawn traffic lights: accepted native exception
        pad = 4 if is_dot else 2
        x0, y0 = int(np.floor(x)) - pad, int(np.floor(y)) - pad
        x1, y1 = int(np.ceil(x + w)) + pad, int(np.ceil(y + h)) + pad
        thr = 10 if is_dot else 20
        bb = ink(B, x0, y0, x1, y1, thr)
        tpl = gB[y0:y1, x0:x1]
        best = None
        for dy in range(-3, 4):
            for dx in range(-3, 4):
                c = gA[y0 + dy:y1 + dy, x0 + dx:x1 + dx]
                s = np.abs(c - tpl).mean()
                if best is None or s < best[0]:
                    best = (s, dx, dy)
        s, mdx, mdy = best
        ab = ink(A, x0 + mdx, y0 + mdy, x1 + mdx, y1 + mdy, thr)
        cxb, cyb = int(x + w / 2), int(y + h / 2)
        cb = hexc(B[cyb, cxb])
        ca = hexc(A[cyb + mdy, cxb + mdx])
        kind = lab.split(" ")[0]
        rows.append([st, kind[:70], f"{x},{y} {w}x{h}",
                     f"{bb[0]},{bb[1]} {bb[2]-bb[0]}x{bb[3]-bb[1]}", f"{ab[0]},{ab[1]} {ab[2]-ab[0]}x{ab[3]-ab[1]}",
                     f"{ab[0]-bb[0]:+d}", f"{ab[1]-bb[1]:+d}", f"{(ab[2]-ab[0])-(bb[2]-bb[0]):+d}", f"{(ab[3]-ab[1])-(bb[3]-bb[1]):+d}",
                     f"({ab[4]-bb[4]:+.2f},{ab[5]-bb[5]:+.2f})", f"match ({mdx},{mdy}) mad={s:.1f}", f"centre board={cb} app={ca}"])
with open("measure-icons.tsv", "w") as fo:
    fo.write("state\ticon\tdom\tboard_ink\tapp_ink\td_left\td_top\td_w\td_h\td_centroid\tmatch\tcentre_px\n")
    for r in rows:
        fo.write("\t".join(r) + "\n")
print(len(rows))
