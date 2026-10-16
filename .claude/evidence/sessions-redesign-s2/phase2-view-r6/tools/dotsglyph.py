# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""dotsglyph.py <img> <px_per_pt> x0,y0,x1,y1   (rect in PIXELS of <img>)
Measures a ring-with-dots glyph: ink bbox, then a horizontal profile through the ink centre row and a
vertical profile through the centre column. Ink = luminance more than half-way from bg to the peak.
Reports run lengths in pt (px / px_per_pt). Mechanical only."""
import sys
import numpy as np
from PIL import Image

path, s = sys.argv[1], float(sys.argv[2])
x0, y0, x1, y1 = [int(v) for v in sys.argv[3].split(",")]
a = np.asarray(Image.open(path).convert("L")).astype(float)[y0:y1, x0:x1]
bg = np.median(np.concatenate([a[0], a[-1], a[:, 0], a[:, -1]]))
peak = a.max()
thr = bg + (peak - bg) * 0.5
ink = a > thr
ys, xs = np.where(ink)
print(f"bg {bg:.0f} peak {peak:.0f} thr {thr:.0f}")
print(f"ink bbox px x {xs.min()}..{xs.max()} y {ys.min()}..{ys.max()} -> {(xs.max()-xs.min()+1)/s:.2f} x {(ys.max()-ys.min()+1)/s:.2f} pt")
cy = int(round((ys.min() + ys.max()) / 2))
cx = int(round((xs.min() + xs.max()) / 2))

def runs(m):
    out, st = [], None
    for i, v in enumerate(m):
        if v and st is None:
            st = i
        if not v and st is not None:
            out.append((st, i)); st = None
    if st is not None:
        out.append((st, len(m)))
    return out

for label, line in (("row", ink[cy]), ("col", ink[:, cx])):
    rs = runs(line)
    print(f"{label} through centre: " + "  ".join(f"[{r0/s:.2f}+{(r1-r0)/s:.2f}]" for r0, r1 in rs))
# dot sizes: components strictly inside the ring, measured on the centre row and columns at each dot centre
rs = runs(ink[cy])
if len(rs) >= 5:
    inner = rs[1:-1]
    for r0, r1 in inner:
        c = (r0 + r1) // 2
        vr = [r for r in runs(ink[:, c]) if r[0] <= cy <= r[1]]
        h = (vr[0][1] - vr[0][0]) / s if vr else 0
        print(f"dot at x {c/s:.2f}: w {(r1-r0)/s:.2f} h {h:.2f} pt; peak lum {a[cy, r0:r1].max():.0f}")
    cs = [((r0 + r1) / 2) / s for r0, r1 in inner]
    print("dot pitch pt:", [round(cs[i+1] - cs[i], 2) for i in range(len(cs) - 1)])
    print(f"ring stroke L {(rs[0][1]-rs[0][0])/s:.2f} R {(rs[-1][1]-rs[-1][0])/s:.2f} pt")
