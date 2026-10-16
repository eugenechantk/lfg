# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Cell pitch of a run of identical glyphs (e.g. a row of W).
usage: period.py <img> x0 y0 x1 y1  (px). Prints the autocorrelation peak (px and pt) and
first/last ink edges, plus per-glyph left edges from the ink column profile."""
import sys
import numpy as np
from PIL import Image

img = np.asarray(Image.open(sys.argv[1]).convert("L")).astype(float)
x0, y0, x1, y1 = [int(v) for v in sys.argv[2:6]]
reg = img[y0:y1, x0:x1]
bg = np.median(reg)
prof = np.abs(reg - bg).sum(axis=0)
p = prof - prof.mean()
ac = np.correlate(p, p, mode="full")[len(p) - 1:]
lo, hi = 15, 30  # px search window (5-10 pt)
k = lo + int(np.argmax(ac[lo:hi]))
# parabolic refinement
y_1, y0_, y1_ = ac[k - 1], ac[k], ac[k + 1]
off = 0.5 * (y_1 - y1_) / (y_1 - 2 * y0_ + y1_)
per = k + off
inkcols = np.where(prof > prof.max() * 0.15)[0]
print(f"period {per:.3f}px = {per / 3:.4f}pt")
print(f"ink x {(x0 + inkcols.min()) / 3:.2f} .. {(x0 + inkcols.max() + 1) / 3:.2f} pt, span {(inkcols.max() + 1 - inkcols.min()) / 3:.2f} pt")
# glyph count by phase: count local maxima groups
thr = prof.max() * 0.15
on = prof > thr
starts = [i for i in range(1, len(on)) if on[i] and not on[i - 1]] + ([0] if on[0] else [])
starts.sort()
print("runs", len(starts), "first starts pt", [round((x0 + s) / 3, 2) for s in starts[:4]], "last", [round((x0 + s) / 3, 2) for s in starts[-3:]])
if len(starts) > 2:
    d = np.diff(starts)
    print(f"mean start spacing {d.mean() / 3:.4f}pt over {len(d)} gaps; (last-first)/(n-1) = {(starts[-1] - starts[0]) / (len(starts) - 1) / 3:.4f}pt")
