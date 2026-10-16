# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""rowprof.py <img> <scale> x0 x1 y0 y1 -> per-1pt-row mean of the brightest 2% of pixels (text ink brightness by row)."""
import sys
import numpy as np
from PIL import Image

a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int).max(axis=2)
s = float(sys.argv[2])
x0, x1, y0, y1 = [float(v) for v in sys.argv[3:7]]
for y in np.arange(y0, y1, 1.0):
    r = a[int(y * s):int((y + 1) * s), int(x0 * s):int(x1 * s)].ravel()
    k = max(1, len(r) // 50)
    top = np.sort(r)[-k:].mean()
    print(f"{y:7.1f} top2% {top:6.1f} max {r.max():3d}")
