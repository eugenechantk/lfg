# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""bands.py <img> <scale> name:x0,x1,y0,y1 ... -> max channel value and p99 in each band (dark-bg bleed check)."""
import sys
import numpy as np
from PIL import Image

a = np.asarray(Image.open(sys.argv[1]).convert("RGB")).astype(int)
s = float(sys.argv[2])
for spec in sys.argv[3:]:
    name, box = spec.split(":")
    x0, x1, y0, y1 = [float(v) for v in box.split(",")]
    r = a[int(y0 * s):int(y1 * s), int(x0 * s):int(x1 * s)]
    m = r.max(axis=2)
    print(f"{name:28s} [{x0:g},{x1:g},{y0:g},{y1:g}] max {m.max():3d} p99 {np.percentile(m, 99):6.1f} p90 {np.percentile(m, 90):6.1f}")
