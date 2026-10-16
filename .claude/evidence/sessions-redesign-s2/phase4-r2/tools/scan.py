# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""scan.py <plan.txt> <img1> [img2 ...]
Plan lines:  <label> row|col <fixed> <from> <to> [tol]
             <label> xruns|yruns <x0> <y0> <x1> <y1> [thr]
             <label> px <x> <y>
For each plan line, prints the result for every image (run-length segments 'start-end:r,g,b' for row/col)."""
import sys
import numpy as np
from PIL import Image

imgs = {p: np.asarray(Image.open(p).convert("RGB")).astype(int) for p in sys.argv[2:]}


def runs(a, mode, fixed, s, e, tol):
    line = a[fixed, s:e] if mode == "row" else a[s:e, fixed]
    out, start = [], 0
    for i in range(1, len(line) + 1):
        if i == len(line) or np.abs(line[i] - line[start]).max() > tol:
            c = tuple(int(v) for v in line[start])
            seg = f"{s+start}-{s+i-1}" if i - 1 > start else f"{s+start}"
            out.append(f"{seg}:{c[0]},{c[1]},{c[2]}")
            start = i
    return "  ".join(out)


def inkruns(a, axis, x0, y0, x1, y1, thr):
    reg = a[y0:y1, x0:x1]
    edge = np.concatenate([reg[0], reg[-1], reg[:, 0], reg[:, -1]])
    bg = np.median(edge, axis=0)
    m = np.abs(reg - bg).max(axis=2) > thr
    m = m.any(axis=0) if axis == "x" else m.any(axis=1)
    off = x0 if axis == "x" else y0
    res, st = [], None
    for i, v in enumerate(list(m) + [False]):
        if v and st is None:
            st = i
        if not v and st is not None:
            res.append((st + off, i - 1 + off)); st = None
    return str(res)


for line in open(sys.argv[1]):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    f = line.split()
    label, kind, nums = f[0], f[1], list(map(int, f[2:]))
    print(f"## {label} ({kind} {' '.join(f[2:])})")
    for p, a in imgs.items():
        name = p.split("/")[-1][:28]
        if kind in ("row", "col"):
            tol = nums[3] if len(nums) > 3 else 2
            r = runs(a, kind, nums[0], nums[1], nums[2], tol)
        elif kind in ("xruns", "yruns"):
            thr = nums[4] if len(nums) > 4 else 22
            r = inkruns(a, kind[0], *nums[:4], thr)
        elif kind == "px":
            r = str(tuple(int(v) for v in a[nums[1], nums[0]]))
        print(f"  {name:28s} {r}")
