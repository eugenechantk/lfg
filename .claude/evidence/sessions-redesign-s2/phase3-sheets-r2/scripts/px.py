# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Pixel measuring helpers for app frames (3x, 1206x2622) and board renders (3x, 1170x2532).

Commands:
  sample <img> x,y [x,y ...]              print RGB at pixel coords
  edges <img> y                            scan a row: print x where colour changes by > 6 levels
  vedges <img> x                           scan a column: print y where colour changes by > 6
  runs <img> x0 y0 x1 y1 [axis] [thr]      ink runs (rows if axis=y, cols if axis=x) vs the region's
                                           modal colour; prints px runs
  bbox <img> x0 y0 x1 y1 [thr]             ink bbox in region vs modal colour
"""
import sys
import numpy as np
from PIL import Image


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(int)


def modal(reg):
    flat = reg.reshape(-1, 3)
    vals, counts = np.unique(flat, axis=0, return_counts=True)
    return vals[counts.argmax()]


def ink_mask(reg, thr):
    bg = modal(reg)
    return np.abs(reg - bg).max(axis=2) > thr, bg


def runs_of(v):
    out, start = [], None
    for i, b in enumerate(v):
        if b and start is None:
            start = i
        if not b and start is not None:
            out.append((start, i - 1)); start = None
    if start is not None:
        out.append((start, len(v) - 1))
    return out


cmd, img = sys.argv[1], sys.argv[2]
a = load(img)
if cmd == "sample":
    for xy in sys.argv[3:]:
        x, y = map(int, xy.split(","))
        print(xy, a[y, x].tolist())
elif cmd == "edges":
    y = int(sys.argv[3]); row = a[y]
    prev = row[0]
    for x in range(1, row.shape[0]):
        if np.abs(row[x] - prev).max() > 6:
            print(x, row[x - 1].tolist(), "->", row[x].tolist())
        prev = row[x]
elif cmd == "vedges":
    x = int(sys.argv[3]); col = a[:, x]
    prev = col[0]
    for y in range(1, col.shape[0]):
        if np.abs(col[y] - prev).max() > 6:
            print(y, col[y - 1].tolist(), "->", col[y].tolist())
        prev = col[y]
elif cmd in ("runs", "bbox"):
    x0, y0, x1, y1 = map(int, sys.argv[3:7])
    reg = a[y0:y1, x0:x1]
    if cmd == "runs":
        axis = sys.argv[7] if len(sys.argv) > 7 else "y"
        thr = int(sys.argv[8]) if len(sys.argv) > 8 else 30
        m, bg = ink_mask(reg, thr)
        v = m.any(axis=1) if axis == "y" else m.any(axis=0)
        off = y0 if axis == "y" else x0
        print("bg", bg.tolist())
        for s, e in runs_of(v):
            sub = m[s:e + 1] if axis == "y" else m[:, s:e + 1]
            other = sub.any(axis=0) if axis == "y" else sub.any(axis=1)
            idx = np.where(other)[0]
            o2 = x0 if axis == "y" else y0
            print(f"{axis} {s+off}-{e+off} (len {e-s+1})  cross {idx.min()+o2}-{idx.max()+o2}")
    else:
        thr = int(sys.argv[7]) if len(sys.argv) > 7 else 30
        m, bg = ink_mask(reg, thr)
        ys, xs = np.where(m)
        print("bg", bg.tolist(), "bbox px", xs.min() + x0, ys.min() + y0, xs.max() + x0, ys.max() + y0)
