"""Stem width of the 'l' in the 'ctrl' key label (half-intensity run, px at 3x) and total ink
coverage of the label, for the board, the app and SF Mono weight references."""
import numpy as np
from PIL import Image
from px import *


def stem_and_ink(a, box):
    x0, y0, x1, y1 = box
    reg = a[y0:y1, x0:x1].mean(axis=2)
    m = reg > 156
    ib = bbox_mask(m)
    ys = ib[1] + max(2, int((ib[3] - ib[1]) * 0.12))
    r = runs(m[ys])
    stem = r[-1][1] - r[-1][0]
    # subpixel stem: sum of normalised intensity across the run +-2 px
    s0, s1 = r[-1][0] - 2, r[-1][1] + 2
    cov = np.clip((reg[ys, s0:s1] - 58) / (255 - 58), 0, 1).sum()
    ink = np.clip((reg - 58) / (255 - 58), 0, 1).sum() / 9.0  # pt^2 of full ink
    return stem, round(float(cov), 2), round(float(ink), 1), (ib[2] - ib[0], ib[3] - ib[1])


B = load("board/board-kbo-fit-3x.png")
A = load("app/term-fit-kbup.png")
print("board ctrl (Menlo Bold 14px)", stem_and_ink(B, (int(110 * 3), int(536 * 3), int(156 * 3), int(562 * 3))))
print("app ctrl", stem_and_ink(A, (int(112 * 3), int(836 * 3), int(159 * 3), int(862 * 3))))
for w in ("regular", "medium", "semibold", "bold"):
    r = np.asarray(Image.open(f"{E}/board/fontref-sfmono-{w}.png").convert("RGB")).astype(int)
    print(f"ref SF Mono {w}", stem_and_ink(r, (0, 0, r.shape[1], r.shape[0])))
