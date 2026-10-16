"""Box / icon / hairline comparison, board vs app (1x, top-aligned).

1. Edges: fixed scan lines through the chrome (segmented track, pill, badges, search button, host dots, By status pill).
   Expected positions come from the board DOM; the nearest same-polarity edge is found in the board profile,
   then the nearest same-polarity edge within +/-4px of it in the app profile. Sub-pixel by gradient centroid.
2. Icons: every <svg> and dot <span> in the state's DOM dump -> ink bbox (low threshold) in both images, plus a
   fill sample at the centre.
3. Hairlines: column scans at x=40, 200, 380 for 1px lines brighter than the local background.
"""
import os
import sys

import numpy as np
from PIL import Image

root = sys.argv[1]
os.chdir(root)
STATES = ["open", "fold-needs", "fold-working", "fold-recent", "fold-all"]


def load(p):
    return np.array(Image.open(p).convert("RGB")).astype(float)


def lum(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def edges(profile, thr=3.0):
    g = np.diff(profile)
    out = []
    for i in range(1, len(g) - 1):
        if abs(g[i]) < thr:
            continue
        if abs(g[i]) >= abs(g[i - 1]) and abs(g[i]) >= abs(g[i + 1]):
            s = np.sign(g[i])
            w = [max(0, s * g[j]) for j in (i - 1, i, i + 1)]
            off = (w[2] - w[0]) / (sum(w) or 1)
            out.append((i + 0.5 + off, s, abs(g[i])))
    return out


def profile(img, axis, line, lo, hi):
    L = lum(img)
    return L[int(line), lo:hi] if axis == "H" else L[lo:hi, int(line)]


EDGE_SPECS = [
    # component, name, axis, line, lo, hi, expected(board DOM), polarity
    ("segmented track", "left", "H", 26, 100, 330, 121.83, +1),
    ("segmented track", "right", "H", 26, 100, 330, 302.17, -1),
    ("segmented track", "top", "V", 228, 0, 50, 10, +1),
    ("segmented track", "bottom", "V", 228, 0, 50, 42, -1),
    ("selected pill", "left", "H", 26, 100, 330, 124.83, +1),
    ("selected pill", "right", "H", 26, 100, 330, 221.6, -1),
    ("selected pill", "top", "V", 130, 0, 50, 13, +1),
    ("selected pill", "bottom", "V", 130, 0, 50, 39, -1),
    ("Sessions badge", "left", "H", 26, 100, 330, 194.59, +1),
    ("Sessions badge", "right", "H", 26, 100, 330, 210.59, -1),
    ("Sessions badge", "top", "V", 202, 0, 50, 18, +1),
    ("Sessions badge", "bottom", "V", 202, 0, 50, 34, -1),
    ("Tasks badge", "left", "H", 26, 100, 330, 272.17, +1),
    ("Tasks badge", "right", "H", 26, 100, 330, 288.17, -1),
    ("Tasks badge", "top", "V", 280, 0, 50, 18, +1),
    ("Tasks badge", "bottom", "V", 280, 0, 50, 34, -1),
    ("search button", "left", "H", 26, 330, 399, 358, +1),
    ("search button", "right", "H", 26, 330, 399, 388, -1),
    ("search button", "top", "V", 373, 0, 50, 11, +1),
    ("search button", "bottom", "V", 373, 0, 50, 41, -1),
    ("Pro dot", "left", "H", 63, 5, 30, 16, +1),
    ("Pro dot", "right", "H", 63, 5, 30, 23, -1),
    ("Pro dot", "top", "V", 19, 53, 75, 59.5, +1),
    ("Pro dot", "bottom", "V", 19, 53, 75, 66.5, -1),
    ("Air ring", "outer left", "H", 63, 52, 76, 62.11, +1),
    ("Air ring", "outer right", "H", 63, 52, 76, 69.11, -1),
    ("Air ring", "outer top", "V", 65, 53, 75, 59.5, +1),
    ("Air ring", "outer bottom", "V", 65, 53, 75, 66.5, -1),
    ("By status pill", "left", "H", 63, 290, 398, 306.17, +1),
    ("By status pill", "right", "H", 63, 290, 398, 384, -1),
    ("By status pill", "top", "V", 310, 53, 80, 52, +1),
    ("By status pill", "bottom", "V", 310, 46, 80, 74, -1),
]


def find_edge(es, target, pol, win):
    c = [e for e in es if e[1] == pol and abs(e[0] - target) <= win]
    if not c:
        return None
    return min(c, key=lambda e: abs(e[0] - target))


def run_edges(B, A, fo, st):
    for comp, name, ax, line, lo, hi, exp, pol in EDGE_SPECS:
        pb, pa = profile(B, ax, line, lo, hi), profile(A, ax, line, lo, hi)
        eb = find_edge(edges(pb), exp - lo, pol, 4)
        if eb is None:
            fo.write(f"{st}\tedge\t{comp}\t{name}\t{ax}@{line}\tboard-edge-missing\n")
            continue
        ea = find_edge(edges(pa), eb[0], pol, 4)
        if ea is None:
            fo.write(f"{st}\tedge\t{comp}\t{name}\t{ax}@{line}\t{eb[0] + lo:.2f}\tapp-edge-missing\n")
            continue
        fo.write(f"{st}\tedge\t{comp}\t{name}\t{ax}@{line}\tdom={exp}\tboard={eb[0] + lo:.2f}\tapp={ea[0] + lo:.2f}\tdelta={ea[0] - eb[0]:+.2f}\n")


def ink_box(img, x0, y0, x1, y1, thr):
    reg = img[y0:y1, x0:x1]
    edge = np.concatenate([reg[0], reg[-1], reg[:, 0], reg[:, -1]])
    bg = np.median(edge, axis=0)
    d = np.abs(lum(reg) - lum(bg[None, None, :]))
    m = d > thr
    if not m.any():
        return None, bg, None
    ys, xs = np.where(m)
    wts = d[m]
    cx = (xs * wts).sum() / wts.sum() + x0 + 0.5
    cy = (ys * wts).sum() / wts.sum() + y0 + 0.5
    k = max(1, len(wts) // 4)
    col = reg[m][np.argsort(wts)[-k:]].mean(axis=0)
    return (x0 + xs.min(), y0 + ys.min(), x0 + xs.max() + 1, y0 + ys.max() + 1, cx, cy), bg, col


def hexc(c):
    return "#%02X%02X%02X" % tuple(int(round(v)) for v in c)


def records(path):
    """DOM dump records; box labels carry textContent with newlines, so re-join continuation lines."""
    recs = []
    for line in open(path):
        line = line.rstrip("\n")
        if line.startswith("text\t") or line.startswith("box\t"):
            recs.append(line)
        elif recs:
            recs[-1] += " " + line.lstrip(" ")  # keep leading tabs: they separate the numeric fields
    out = []
    for r in recs:
        f = r.split("\t")
        # labels may contain stray tabs from textContent: locate the first run of 4 numeric fields
        for i in range(2, len(f) - 3):
            try:
                nums = [float(v) for v in f[i:i + 4]]
            except ValueError:
                continue
            out.append([f[0], " ".join(f[1:i]).strip()] + f[i:])
            break
    return out


def run_icons(B, A, fo, st):
    for f in records(f"board-dom-{st}.tsv"):
        if f[0] != "box":
            continue
        lab = f[1]
        x, y, w, h = map(float, f[2:6])
        is_svg = lab.startswith("svg")
        is_dot = lab.startswith("span") and w <= 12 and h <= 12
        if not (is_svg or is_dot):
            continue
        pad = 5 if is_dot else 3
        x0, y0, x1, y1 = int(x) - pad, int(y) - pad, int(np.ceil(x + w)) + pad, int(np.ceil(y + h)) + pad
        thr = 10 if is_dot else 20
        bb, bbg, bcol = ink_box(B, x0, y0, x1, y1, thr)
        # app: search a slightly larger window so a 1-2px offset still lands inside
        ab, abg, acol = ink_box(A, x0 - 2, y0 - 2, x1 + 2, y1 + 2, thr)
        name = lab.split(" ")[0][:60]
        if bb is None or ab is None:
            fo.write(f"{st}\ticon\t{name}\t@{x},{y}\tmissing board={bb is not None} app={ab is not None}\n")
            continue
        fo.write(
            f"{st}\ticon\t{name}\t@{x},{y} {w}x{h}\tboard={bb[0]},{bb[1]} {bb[2]-bb[0]}x{bb[3]-bb[1]} c=({bb[4]:.1f},{bb[5]:.1f})"
            f"\tapp={ab[0]},{ab[1]} {ab[2]-ab[0]}x{ab[3]-ab[1]} c=({ab[4]:.1f},{ab[5]:.1f})"
            f"\tdc=({ab[4]-bb[4]:+.1f},{ab[5]-bb[5]:+.1f}) dsize=({(ab[2]-ab[0])-(bb[2]-bb[0]):+d},{(ab[3]-ab[1])-(bb[3]-bb[1]):+d})"
            f"\tcol board={hexc(bcol)} app={hexc(acol)}\n"
        )


def run_hairlines(B, A, fo, st):
    for x in (40, 200, 380):
        for nm, img in (("board", B), ("app", A)):
            L = lum(img)[:, x]
            rows = []
            for y in range(53, min(img.shape[0], 860) - 1):
                if L[y] - L[y - 1] >= 4 and L[y] - L[y + 1] >= 4 and L[y] - max(L[y - 2], L[y + 2]) >= 4 and L[y] < 80:
                    rows.append(f"{y}:{hexc(img[y, x])}")
            fo.write(f"{st}\thairlines\tx={x}\t{nm}\t{' '.join(rows)}\n")


if __name__ != "__main__":
    pass
else:
  with open("measure-boxes.tsv", "w") as fo:
    for st in STATES:
        B, A = load(f"board-{st}.png"), load(f"app-{st}-srgb.png")
        if st == "open":
            run_edges(B, A, fo, st)
        run_icons(B, A, fo, st)
        run_hairlines(B, A, fo, st)
print("ok")
