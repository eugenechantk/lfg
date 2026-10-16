"""Per-text-element ink comparison, board capture vs app capture (both 1x, top-aligned).

For every text run in board-dom-<state>.tsv:
  1. board ink bbox inside the DOM range rect (+2px pad);
  2. template-match the board ink crop over the app within +/-9px to find the app's copy;
  3. app ink bbox inside the matched window (+3px pad);
  4. report left/top/right/bottom deltas (app - board, px == pt at 1x), size deltas, and ink colour
     (mean of the 25% most contrasting ink pixels, sRGB) for both.
Output TSV to measure-text-<state>.tsv.
"""
import os
import sys

import numpy as np
from PIL import Image

root = sys.argv[1]
os.chdir(root)
STATES = sys.argv[2:] or ["open", "fold-needs", "fold-working", "fold-recent", "fold-all"]
THR = 26  # luminance delta from local background that counts as ink


def lum(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def bg_of(rgb, x0, y0, x1, y1):
    reg = rgb[y0:y1, x0:x1].reshape(-1, 3)
    edge = np.concatenate([rgb[y0, x0:x1], rgb[y1 - 1, x0:x1], rgb[y0:y1, x0], rgb[y0:y1, x1 - 1]])
    return np.median(edge, axis=0)


def ink_box(rgb, x0, y0, x1, y1, bg=None):
    x0, y0 = max(0, x0), max(0, y0)
    x1, y1 = min(rgb.shape[1], x1), min(rgb.shape[0], y1)
    if bg is None:
        bg = bg_of(rgb, x0, y0, x1, y1)
    reg = rgb[y0:y1, x0:x1].astype(float)
    d = np.abs(lum(reg) - lum(np.array(bg, dtype=float)[None, None, :]))
    m = d > THR
    if not m.any():
        return None, bg, None
    ys, xs = np.where(m)
    box = (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1)
    # ink colour: mean of the most contrasting quarter of ink pixels
    vals = reg[m]
    dd = d[m]
    k = max(1, len(dd) // 4)
    idx = np.argsort(dd)[-k:]
    col = vals[idx].mean(axis=0)
    return box, bg, col


def load(path):
    return np.array(Image.open(path).convert("RGB")).astype(float)


for st in STATES:
    B = load(f"board-{st}.png")
    A = load(f"app-{st}-srgb.png")
    gB, gA = lum(B), lum(A)
    rows = []
    for line in open(f"board-dom-{st}.tsv"):
        f = line.rstrip("\n").split("\t")
        if f[0] != "text":
            continue
        name = f[1]
        x, y, w, h = map(float, f[2:6])
        bx0, by0, bx1, by1 = int(np.floor(x)) - 2, int(np.floor(y)) - 1, int(np.ceil(x + w)) + 2, int(np.ceil(y + h)) + 1
        bbox, bg, bcol = ink_box(B, bx0, by0, bx1, by1)
        if bbox is None:
            rows.append([st, name, "no-board-ink"])
            continue
        l, t, r, b = bbox
        tpl = gB[t - 1:b + 1, l - 1:r + 1]
        best = None
        for dy in range(-9, 10):
            for dx in range(-9, 10):
                yy, xx = t - 1 + dy, l - 1 + dx
                if yy < 0 or xx < 0 or yy + tpl.shape[0] > gA.shape[0] or xx + tpl.shape[1] > gA.shape[1]:
                    continue
                cand = gA[yy:yy + tpl.shape[0], xx:xx + tpl.shape[1]]
                s = np.abs(cand - tpl).mean()
                if best is None or s < best[0]:
                    best = (s, dx, dy)
        s, mdx, mdy = best
        abox, abg, acol = ink_box(A, l - 3 + mdx, t - 3 + mdy, r + 3 + mdx, b + 3 + mdy, bg=None)
        if abox is None:
            rows.append([st, name, "no-app-ink"])
            continue
        al, at, ar, ab = abox
        rows.append([
            st, name,
            f"{l},{t},{r - l}x{b - t}", f"{al},{at},{ar - al}x{ab - at}",
            al - l, at - t, ar - r, ab - b, (ar - al) - (r - l), (ab - at) - (b - t),
            f"match dx={mdx} dy={mdy} mad={s:.1f}",
            "#%02X%02X%02X" % tuple(int(round(c)) for c in bcol), "#%02X%02X%02X" % tuple(int(round(c)) for c in acol),
            "bg #%02X%02X%02X/#%02X%02X%02X" % (tuple(int(c) for c in bg) + tuple(int(c) for c in abg)),
        ])
    with open(f"measure-text-{st}.tsv", "w") as fo:
        fo.write("state\ttext\tboard_ink(x,y,wxh)\tapp_ink\td_left\td_top\td_right\td_bottom\td_w\td_h\tmatch\tboard_ink_col\tapp_ink_col\tbg\n")
        for r in rows:
            fo.write("\t".join(str(c) for c in r) + "\n")
    print(st, len(rows))
