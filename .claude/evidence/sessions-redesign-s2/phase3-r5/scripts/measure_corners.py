"""Corner contour comparison: max normal distance between the board and app top-left corner
contours of a shape (px -> pt). Contour = first filled x per row, from the shape's top edge."""
import numpy as np
from px import *


def contour(a, x0, y0, n, bg, thr):
    pts = []
    for k in range(n):
        row = np.abs(a[y0 + k, x0:x0 + n + 10] - np.array(bg)).max(axis=1) > thr
        idx = np.where(row)[0]
        if len(idx):
            pts.append((idx[0], k))
    return np.array(pts, dtype=float)


def maxdist(c1, c2):
    d = np.sqrt(((c1[:, None, :] - c2[None, :, :]) ** 2).sum(axis=2)).min(axis=1)
    return round(d.max() / 3, 2), round(d.mean() / 3, 2)


def lum_bbox(a, x0, y0, x1, y1, lo, hi):
    return bbox_lum(a, x0, y0, x1, y1, lo, hi)


cases = []
B = load("board/board-signin-3x.png"); A = load("app/signin.png")
# close button: fill lum ~45 vs sheet ~29
cb = lum_bbox(B, 30, 64 * 3, 170, 110 * 3, 36, 70); ca = lum_bbox(A, 30, 72 * 3, 170, 118 * 3, 36, 70)
print("E close circle bbox board", pt(cb, 0, 54), "app", pt(ca, 0, 62))
rb = lum_bbox(B, 330 * 3, 64 * 3, 389 * 3, 110 * 3, 36, 70); ra = lum_bbox(A, 342 * 3, 72 * 3, 401 * 3, 118 * 3, 36, 70)
print("E reload circle bbox board", pt(rb, 0, 54), "right inset", round(390 - rb[2] / 3, 2), "app", pt(ra, 0, 62), "right inset", round(402 - ra[2] / 3, 2))
print("E close fill board", hexc(color_at(B, cb[0] + 12, (cb[1] + cb[3]) // 2)), "app", hexc(color_at(A, ca[0] + 12, (ca[1] + ca[3]) // 2)))
sheetB, sheetA = (28, 28, 30), (26, 26, 28)
cases.append(("E close circle", B, A, cb[0], cb[1], ca[0], ca[1], 60, sheetB, sheetA, 6))
cases.append(("E pill", B, A, 58 * 3, 67 * 3, 58 * 3, 75 * 3, 40, sheetB, sheetA, 6))
cases.append(("E done button", B, A, 114 * 3, 763 * 3, 114 * 3, 793 * 3, 75, sheetB, sheetA, 40))
cases.append(("E back button", B, A, 10 * 3, 766 * 3, 10 * 3, 796 * 3, 66, sheetB, sheetA, 6))
cases.append(("E sheet corner", B, A, 0, 54 * 3, 0, 62 * 3, 114, (0, 0, 0), (0, 0, 0), 10))
Bt = load("board/board-kbc-fit-3x.png"); At = load("app/term-fit-kbhidden-keystart.png")
cases.append(("D close circle", Bt, At, 12 * 3, 58 * 3, 12 * 3, 66 * 3, 66, (11, 11, 13), (10, 10, 12), 12))
cases.append(("D seg outer", Bt, At, 286 * 3, 64 * 3, 298 * 3, 72 * 3, 48, (11, 11, 13), (10, 10, 12), 12))
cases.append(("D esc key", Bt, At, 8 * 3, 2302, 8 * 3, 2388, 30, (28, 28, 30), (26, 26, 28), 14))
for name, b, a, bx, by, ax, ay, n, bgb, bga, thr in cases:
    c1 = contour(b, bx, by, n, bgb, thr); c2 = contour(a, ax, ay, n, bga, thr)
    print(f"{name:16s} contour rows {len(c1)}/{len(c2)}  max normal distance {maxdist(c1, c2)[0]} pt, mean {maxdist(c1, c2)[1]} pt; first-row inset px board {int(c1[0][0])} app {int(c2[0][0])}")
