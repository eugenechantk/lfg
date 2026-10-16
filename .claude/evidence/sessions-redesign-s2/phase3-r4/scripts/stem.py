# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Stem width of a vertical stroke: for each row in the box, width of the longest ink run
(coverage-weighted: sum of (pixel-bg)/(peak-bg) across the run). Reports the median in px and pt.
usage: stem.py <img> x0 y0 x1 y1 (px)"""
import sys
import numpy as np
from PIL import Image

img = np.asarray(Image.open(sys.argv[1]).convert("L")).astype(float)
x0, y0, x1, y1 = [int(v) for v in sys.argv[2:6]]
reg = img[y0:y1, x0:x1]
bg = np.median(np.concatenate([reg[:, 0], reg[:, -1]]))
peak = reg.max()
cov = np.clip((reg - bg) / (peak - bg), 0, 1)
w = cov.sum(axis=1)
w = w[w > 0.5]
print(f"bg {bg:.0f} peak {peak:.0f} rows {len(w)} median coverage width {np.median(w):.2f}px = {np.median(w) / 3:.3f}pt")
