# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""E follow-up: web-content bottom edge, nav button extents/fills, subtitle orange."""
import numpy as np
from lib import load

B = load("board/board-signin-appvalues-3x.png")
A = load("app/signin.png")
for nm, img, T in (("board", B, 54.0), ("app", A, 62.0)):
    H = img.shape[0] / 3; W = img.shape[1] / 3
    col = img[int((H - 130) * 3):, int(200 * 3)]
    prev = col[0]
    ed = []
    for i in range(1, len(col)):
        if np.abs(col[i] - col[i - 1]).max() > 2:
            ed.append((round(H - (int((H - 130) * 3) + i) / 3, 2), col[i].tolist()))
    print(nm, "x=200 transitions from bottom (thr 2):", ed[:6], "...", ed[-4:])
    row = img[int((H - 56) * 3), : int(120 * 3)]
    print(nm, "row H-56 profile every 1pt x 0..60:", [int(row[int(x * 3)].max()) for x in range(0, 60, 2)])
    colb = img[int((H - 90) * 3):, int(32 * 3)]
    print(nm, "col x=32 profile every 2pt from H-90:", [int(colb[int(y * 3)].max()) for y in range(0, 90, 2)])
    reg = img[int((T + 38) * 3):int((T + 46) * 3), int(100 * 3):int((W - 100) * 3)].reshape(-1, 3)
    orange = reg[(reg[:, 0] > 150) & (reg[:, 0] - reg[:, 2] > 80)]
    print(nm, "subtitle orange pixels n=%d  p90 R,G,B" % len(orange), np.percentile(orange, 90, axis=0).round(1).tolist() if len(orange) else None)
