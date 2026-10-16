# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Pixel probe for design/app frames. Coordinates are in logical points; scale = px per pt.

usage:
  m.py rows <img> <scale> x0 x1 y0 y1 [bg=000000] [thr=40]   -> ink runs along y (pt)
  m.py cols <img> <scale> x0 x1 y0 y1 [bg=000000] [thr=40]   -> ink runs along x (pt)
  m.py px   <img> <scale> x y [x y ...]                       -> mean colour of the 1pt cell
  m.py vline <img> <scale> x y0 y1                            -> colour transitions down a column
  m.py hline <img> <scale> y x0 x1                            -> colour transitions across a row
"""
import sys
import numpy as np
from PIL import Image

def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(np.int32)

def hexc(c):
    return "#%02X%02X%02X" % tuple(int(round(v)) for v in c)

def runs(mask):
    out, start = [], None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        if not v and start is not None:
            out.append((start, i)); start = None
    if start is not None:
        out.append((start, len(mask)))
    return out

def parse_bg(s):
    return np.array([int(s[i:i+2], 16) for i in (0, 2, 4)])

def main():
    cmd, path, scale = sys.argv[1], sys.argv[2], float(sys.argv[3])
    a = load(path)
    args = sys.argv[4:]
    if cmd in ("rows", "cols"):
        x0, x1, y0, y1 = [float(v) for v in args[:4]]
        bg = parse_bg(args[4]) if len(args) > 4 else np.array([0, 0, 0])
        thr = float(args[5]) if len(args) > 5 else 40
        X0, X1, Y0, Y1 = [int(round(v * scale)) for v in (x0, x1, y0, y1)]
        sub = a[Y0:Y1, X0:X1]
        dev = np.abs(sub - bg).max(axis=2)
        mask = (dev > thr).any(axis=1 if cmd == "rows" else 0)
        base = Y0 if cmd == "rows" else X0
        for s, e in runs(mask):
            if cmd == "rows":
                seg = sub[s:e]
            else:
                seg = sub[:, s:e]
            d = np.abs(seg - bg).max(axis=2)
            idx = np.unravel_index(np.argmax(d), d.shape)
            peak = seg[idx]
            print(f"{(base+s)/scale:8.2f} -> {(base+e)/scale:8.2f}  len {(e-s)/scale:6.2f}  peak {hexc(peak)}")
    elif cmd == "px":
        vals = [float(v) for v in args]
        for i in range(0, len(vals), 2):
            x, y = vals[i], vals[i+1]
            X, Y = int(x * scale), int(y * scale)
            n = max(1, int(scale))
            cell = a[Y:Y+n, X:X+n].reshape(-1, 3).mean(axis=0)
            print(f"({x},{y}) {hexc(cell)}")
    elif cmd in ("vline", "hline"):
        c, s0, s1 = [float(v) for v in args[:3]]
        thr = float(args[3]) if len(args) > 3 else 12
        C = int(c * scale)
        S0, S1 = int(s0 * scale), int(s1 * scale)
        line = a[S0:S1, C] if cmd == "vline" else a[C, S0:S1]
        prev = None; start = S0
        segs = []
        for i, p in enumerate(line):
            if prev is None or np.abs(p - prev).max() > thr:
                segs.append([S0 + i, p])
            prev = p
        for j, (st, p) in enumerate(segs):
            en = segs[j+1][0] if j + 1 < len(segs) else S1
            if (en - st) >= 1:
                print(f"{st/scale:8.2f} -> {en/scale:8.2f}  {hexc(p)}")

main()
