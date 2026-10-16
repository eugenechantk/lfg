"""Extra / missing element check per state.

Ink mask = |lum - local bg lum| > 18 (bg = body #1B1B1E-ish). Board mask dilated by 4px; app ink outside it = app-only
ink (extra element or >4px shift). Same the other way for board-only ink (missing element). Connected regions are
reported with their bbox and pixel count. Window-chrome rows y<52 and the app's rows below 860 are reported separately.
"""
import os
import sys

import numpy as np
from PIL import Image

root = sys.argv[1]
os.chdir(root)
STATES = ["open", "fold-needs", "fold-working", "fold-recent", "fold-all"]


def lum(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def dilate(m, r):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def regions(m):
    seen = np.zeros_like(m)
    H, W = m.shape
    res = []
    for y, x in zip(*np.where(m)):
        if seen[y, x]:
            continue
        stack = [(y, x)]
        seen[y, x] = True
        pts = []
        while stack:
            cy, cx = stack.pop()
            pts.append((cy, cx))
            for ny, nx in ((cy + 1, cx), (cy - 1, cx), (cy, cx + 1), (cy, cx - 1)):
                if 0 <= ny < H and 0 <= nx < W and m[ny, nx] and not seen[ny, nx]:
                    seen[ny, nx] = True
                    stack.append((ny, nx))
        ys = [p[0] for p in pts]
        xs = [p[1] for p in pts]
        res.append((min(xs), min(ys), max(xs) + 1, max(ys) + 1, len(pts)))
    return res


with open("residual.txt", "w") as fo:
    for st in STATES:
        B = np.array(Image.open(f"board-{st}.png").convert("RGB")).astype(float)
        A = np.array(Image.open(f"app-{st}-srgb.png").convert("RGB")).astype(float)[:860]
        bg = lum(np.array([27.0, 27.0, 30.0]))
        mb = np.abs(lum(B) - bg) > 18
        ma = np.abs(lum(A) - bg) > 18
        mb[:52] = ma[:52] = False  # title-bar band handled by edge/fill checks (native controls, harness shade)
        app_only = ma & ~dilate(mb, 4)
        board_only = mb & ~dilate(ma, 4)
        fo.write(f"== {st}\n")
        for nm, m in (("app-only", app_only), ("board-only", board_only)):
            rs = [r for r in regions(m) if r[4] >= 3]
            fo.write(f"{nm}: {len(rs)} regions (>=3px)\n")
            for r in sorted(rs, key=lambda r: (r[1], r[0])):
                fo.write(f"  x={r[0]}..{r[2]} y={r[1]}..{r[3]} px={r[4]}\n")
        # app pixels below 860 (harness window is 912 tall): anything but background?
        A2 = np.array(Image.open(f"app-{st}-srgb.png").convert("RGB")).astype(float)
        tail = A2[860:, 2:-2]
        fo.write(f"app rows 860..{A2.shape[0]}: max |lum-bg| = {np.abs(lum(tail) - bg).max():.1f}\n")
print(open("residual.txt").read())
