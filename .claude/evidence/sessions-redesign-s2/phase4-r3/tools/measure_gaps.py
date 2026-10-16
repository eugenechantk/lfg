"""Judge the coordinator's on-screen captures of the current build (gaps G1, G2).

G1: title band on screen (active + inactive) vs board: column profiles y=0..95, title-bar bg, presence of a y=51 line,
    top-bar control fills/edges (segmented track, selected pill, search button, By status pill), active vs inactive diff.
G2: click fold: header/row geometry before, after the first click, after the second click; chevron ink; hint presence.
"""
import os

import numpy as np
from PIL import Image

R = "/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase4-r3"
os.chdir(R)


def load(p):
    return np.array(Image.open(p).convert("RGB")).astype(int)


def lum(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def hx(p):
    return "#%02X%02X%02X" % tuple(int(v) for v in p)


board = load("board-open.png")
harn = load("app-open-srgb.png")
act = load("gaps/active-before-click-srgb.png")
fold = load("gaps/after-click-folded-srgb.png")
reop = load("gaps/after-second-click-open-srgb.png")
inact = load("gaps/inactive-srgb.png")

print("== G1 title band: column x=150 and x=250, rows 0..95 (lines/fills only, runs collapsed)")
for nm, img in (("board", board), ("harness", harn), ("onscreen-active", act), ("onscreen-inactive", inact)):
    for x in (100, 250):
        runs, prev, start = [], None, 0
        for y in range(0, 96):
            c = hx(img[y, x])
            if c != prev:
                if prev is not None:
                    runs.append(f"{start}-{y - 1}:{prev}")
                prev, start = c, y
        runs.append(f"{start}-95:{prev}")
        print(f"{nm:18s} x={x}: " + " ".join(runs))

print("\n== G1 fills (board / harness / on-screen active / on-screen inactive)")
for nm, (x, y) in {
    "title bar bg (100,5)": (100, 5), "title bar bg (300,48)": (300, 48), "y=51 at x=100": (100, 51),
    "body bg (200,70)": (200, 70), "list top border (100,82)": (100, 82),
    "segmented track (x=? y=11)": (150, 11), "selected pill (160,26)": (160, 26),
    "search button (362,26)": (362, 26), "By status pill (310,63)": (310, 63),
}.items():
    print(f"{nm:30s} {hx(board[y, x])}  {hx(harn[y, x])}  {hx(act[y, x])}  {hx(inact[y, x])}")

d = np.abs(act - inact).max(axis=2)
ys, xs = np.where(d > 3)
print(f"\nactive vs inactive on screen: {len(ys)} px differ (>3)", "bbox" if len(ys) else "",
      (xs.min(), ys.min(), xs.max(), ys.max()) if len(ys) else "")


def edges_h(img, y, lo, hi, thr=3):
    L = lum(img[y, lo:hi])
    g = np.diff(L)
    return [(lo + i + 0.5, int(np.sign(g[i]))) for i in range(1, len(g) - 1)
            if abs(g[i]) >= thr and abs(g[i]) >= abs(g[i - 1]) and abs(g[i]) >= abs(g[i + 1])]


def edges_v(img, x, lo, hi, thr=3):
    L = lum(img[lo:hi, x])
    g = np.diff(L)
    return [(lo + i + 0.5, int(np.sign(g[i]))) for i in range(1, len(g) - 1)
            if abs(g[i]) >= thr and abs(g[i]) >= abs(g[i - 1]) and abs(g[i]) >= abs(g[i + 1])]


print("\n== G1 top-bar geometry on screen (edges, pt)")
for nm, img in (("board", board), ("harness", harn), ("active", act), ("inactive", inact)):
    print(f"{nm:9s} track/pill V@x=128: {[e for e in edges_v(img, 128, 0, 50)][:8]}")
    print(f"{nm:9s} search V@x=373: {[e for e in edges_v(img, 373, 0, 50)][:2]} H@y=14: {[e for e in edges_h(img, 14, 340, 399)][:3]}")
    print(f"{nm:9s} ByStatus H@y=56: {[e for e in edges_h(img, 56, 290, 399)][:2]} V@x=310: {[e for e in edges_v(img, 310, 40, 80)]}")
    print(f"{nm:9s} Pro dot H@y=63: {[e for e in edges_h(img, 63, 5, 30)][:2]}")


def ink_rows(img, x0, x1, y0, y1, thr=26):
    """Return list of (top,bottom) runs of rows that contain ink in [x0,x1)."""
    bgl = lum(np.array([27.0, 27.0, 30.0]))
    m = (np.abs(lum(img[y0:y1, x0:x1]) - bgl) > thr).any(axis=1)
    runs, inrun = [], False
    for i, v in enumerate(m):
        if v and not inrun:
            s, inrun = i, True
        elif not v and inrun:
            runs.append((y0 + s, y0 + i - 1))
            inrun = False
    if inrun:
        runs.append((y0 + s, y1 - 1))
    return runs


print("\n== G2 header/row structure (ink row runs in the label column x=37..120, y=84..330)")
for nm, img in (("board open", board), ("board fold-working", load("board-fold-working.png")), ("board fold-all", load("board-fold-all.png")),
                ("onscreen before", act), ("onscreen after 1st click", fold), ("onscreen after 2nd click", reop)):
    print(f"{nm:26s}", ink_rows(img, 37, 120, 84, 330))
print("\n== G2 chevron ink (x=16..31) per header, and hint ink (x=300..390)")


def ink_box(img, x0, y0, x1, y1, thr=20):
    reg = img[y0:y1, x0:x1].astype(float)
    edge = np.concatenate([reg[0], reg[-1], reg[:, 0], reg[:, -1]])
    bg = np.median(edge, axis=0)
    m = np.abs(lum(reg) - lum(bg[None, None, :])) > thr
    if not m.any():
        return None
    ys, xs = np.where(m)
    return (x0 + xs.min(), y0 + ys.min(), xs.max() - xs.min() + 1, ys.max() - ys.min() + 1)


for nm, img, hdrs in (("board open", board, [100, 288, 551]), ("board fold-working", load("board-fold-working.png"), [288]),
                      ("board fold-all", load("board-fold-all.png"), [100, 137, 175]),
                      ("onscreen before", act, None), ("onscreen after 1st", fold, None), ("onscreen after 2nd", reop, None)):
    if hdrs is None:
        # header label rows: find runs whose label starts at x=37 with grey/amber header weight; use runs from ink_rows
        runs = [r for r in ink_rows(img, 37, 120, 84, 330)]
        hdrs = []
        for (t, b) in runs:
            # a header has a chevron at x=18..29 on the same rows
            if ink_box(img, 16, t - 3, 32, b + 4) is not None and ink_box(img, 0, t - 3, 14, b + 4) is None:
                hdrs.append(t)
    for t in hdrs:
        cb = ink_box(img, 16, t - 4, 32, t + 13)
        hb = ink_box(img, 290, t - 3, 392, t + 13)
        print(f"{nm:20s} header@{t}: chevron={cb} hint={hb}")

print("\nbefore vs after-2nd-click identical:", bool((act == reop).all()))
