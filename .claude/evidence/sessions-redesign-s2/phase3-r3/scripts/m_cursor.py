# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Cursor colour over a 3 s recording (blink). Cursor cell ~x 76-84 pt, y 124-140 pt."""
import glob, os
from lib import *

vals = []
for f in sorted(glob.glob(os.path.join(E, "app", "cursorframes", "*.png"))):
    a = load(os.path.relpath(f, E))
    c = a[372:378, 236:246].reshape(-1, 3).mean(axis=0)
    t = a[375:415, 36:200].max(axis=(0, 1))
    vals.append((os.path.basename(f), [round(v) for v in c], t.tolist()))
cs = [v[1][0] for v in vals]
print("frames", len(vals), " cursor centre min", min(cs), " max", max(cs))
from collections import Counter
print("histogram (cursor R, rounded to 10):", sorted(Counter([round(c, -1) for c in cs]).items()))
print("prompt text peak across frames:", sorted(set(tuple(v[2]) for v in vals))[:5])
