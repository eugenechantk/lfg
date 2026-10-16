# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Generic probes. All coordinates are image px; output px(pt = px/3).
usage: probe.py <img> rows|cols|bbox x0 y0 x1 y1 [thr]
       probe.py <img> vedge x y0 y1 [thr] | hedge y x0 x1 [thr] | px x y | mean x0 y0 x1 y1"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ink, rows, cols, bbox, vedges, hedges
import numpy as np
from PIL import Image

img = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
cmd = sys.argv[2]
a = [int(v) for v in sys.argv[3:]]


def f(v):
    return f"{v}({v / 3:.2f})"


if cmd in ("rows", "cols"):
    thr = a[4] if len(a) > 4 else 30
    fn = rows if cmd == "rows" else cols
    m, bg = ink(img, a[0], a[1], a[2], a[3], thr)
    print("bg", bg.tolist())
    for r in fn(img, a[0], a[1], a[2], a[3], thr):
        print(" ".join(f(v) for v in r), " w", round((r[1] - r[0]) / 3, 2) if cmd == "cols" else round((r[1] - r[0]) / 3, 2))
elif cmd == "bbox":
    thr = a[4] if len(a) > 4 else 30
    b = bbox(img, a[0], a[1], a[2], a[3], thr)
    print(" ".join(f(v) for v in b), "w", round((b[2] - b[0]) / 3, 2), "h", round((b[3] - b[1]) / 3, 2))
elif cmd == "vedge":
    for e in vedges(img, a[0], a[1], a[2], a[3] if len(a) > 3 else 6):
        print(f(e[0]), e[1], e[2])
elif cmd == "hedge":
    for e in hedges(img, a[0], a[1], a[2], a[3] if len(a) > 3 else 6):
        print(f(e[0]), e[1], e[2])
elif cmd == "px":
    print(img[a[1], a[0]].tolist())
elif cmd == "mean":
    reg = img[a[1]:a[3], a[0]:a[2]].reshape(-1, 3)
    print("mean", reg.mean(axis=0).round(1).tolist(), "p50", np.percentile(reg, 50, axis=0).tolist(),
          "max-ch p90", np.percentile(reg.max(axis=1), 90), "p98", np.percentile(reg.max(axis=1), 98))
