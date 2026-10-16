# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""B (subagents), C (files), C-links measurements in sheet pt. Board sheet top 200."""
import numpy as np
from sheet import Sheet


def pct(s, x0, y0, x1, y1, q, floor=60):
    X0, Y0, X1, Y1 = s.box(x0, y0, x1, y1)
    g = s.a[Y0:Y1, X0:X1].max(axis=2).reshape(-1)
    g = g[g > floor]
    return round(float(np.percentile(g, q)), 1) if len(g) else None


def show(t, rb, ra):
    print(f"-- {t}\n   board: {rb}\n   app  : {ra}")


def header(b, a):
    show("title/subtitle rows", b.rows(18, 15, 240, 72, 40)[0], a.rows(18, 15, 240, 72, 40)[0])
    bc = [e[0] for e in b.hscan(38, b.W - 60, b.W - 1, 6)]; ac = [e[0] for e in a.hscan(38, a.W - 60, a.W - 1, 6)]
    show("close x (first,last) / right inset", (bc[0], bc[-1], round(b.W - bc[-1], 2)), (ac[0], ac[-1], round(a.W - ac[-1], 2)))
    bv = [e[0] for e in b.vscan(b.W - 34, 10, 64, 6)]; av = [e[0] for e in a.vscan(a.W - 34, 10, 64, 6)]
    show("close y (first,last)", (bv[0], bv[-1]), (av[0], av[-1]))
    show("close fill / glyph peak", (b.sample(b.W - 46, 38), b.peak(b.W - 40, 32, b.W - 28, 44)), (a.sample(a.W - 46, 38), a.peak(a.W - 40, 32, a.W - 28, 44)))


def seps(s, x, y0, y1):
    """separator lines: runs of rows brighter than the sheet bg at column x"""
    X, Y0 = s.px(x, y0); _, Y1 = s.px(x, y1)
    col = s.a[Y0:Y1, X].max(axis=1)
    bg = np.median(col)
    out, start = [], None
    for i, v in enumerate(col):
        if v > bg + 8 and start is None:
            start = i
        if v <= bg + 8 and start is not None:
            out.append((s.pty(Y0 + start), round((i - start) / 3 / s.s, 2), int(col[start:i].max()))); start = None
    return out


print("=================== B subagents")
b = Sheet("board", "board/board-subagents-3x.png", btop=200)
a = Sheet("app", "app/subagents.png", gname="subagents")
header(b, a)
show("separators at x=300 (y, thickness pt, peak)", seps(b, 300, 80, 460), seps(a, 300, 80, 460))
show("separator left edge (hscan just on first sep)", [e[0] for e in b.hscan(seps(b, 300, 80, 460)[0][0] + 0.1, 0, 120, 6)],
     [e[0] for e in a.hscan(seps(a, 300, 80, 460)[0][0] + 0.1, 0, 120, 6)])
for i in range(4):
    by0 = 88 + i * 87.4; ay0 = 88 + i * 88.0
    show(f"row {i} icon bbox", b.bbox(16, by0 + 4, 46, by0 + 34, 30), a.bbox(16, ay0 + 4, 46, ay0 + 34, 30))
    show(f"row {i} text rows", b.rows(52, by0 + 2, 330, by0 + 84, 40)[0], a.rows(52, ay0 + 2, 340, ay0 + 84, 40)[0])
    bb = b.bbox(b.W - 34, by0 + 25, b.W - 12, by0 + 60, 12, bg=b.sample(b.W - 40, by0 + 20))
    ab = a.bbox(a.W - 34, ay0 + 25, a.W - 12, ay0 + 60, 12, bg=a.sample(a.W - 40, ay0 + 20))
    show(f"row {i} chevron bbox / right inset / size", (bb, round(b.W - bb[2], 2), round(bb[2] - bb[0], 2), round(bb[3] - bb[1], 2)),
         (ab, round(a.W - ab[2], 2), round(ab[2] - ab[0], 2), round(ab[3] - ab[1], 2)))
show("running dot core / ring", (b.sample(31, 104.5), b.sample(31, 99)), (a.sample(31, 104.5), a.sample(31, 99)))
for nm, s in (("board", b), ("app", a)):
    print(nm, "p98: title", pct(s, 54, 99, 300, 115, 98), " running green", pct(s, 54, 122, 140, 138, 98), " result grey", pct(s, 54, 210, 300, 226, 98),
          " meta", pct(s, 54, 145, 200, 158, 98), " failed red", s.peak(54, 385, 220, 400), " subtitle", pct(s, 20, 55, 200, 68, 98))

print("=================== C files")
b = Sheet("board", "board/board-files-3x.png", btop=200)
a = Sheet("app", "app/files.png", gname="files")
header(b, a)
show("pill track hscan y=101", [e[0] for e in b.hscan(101, 0, b.W, 6)][:3] + [e[0] for e in b.hscan(101, 0, b.W, 6)][-3:],
     [e[0] for e in a.hscan(101, 0, a.W, 6)][:3] + [e[0] for e in a.hscan(101, 0, a.W, 6)][-3:])
show("pill vscan x=100", [e[0] for e in b.vscan(100, 76, 126, 6)], [e[0] for e in a.vscan(100, 76, 126, 6)])
show("pill vscan x=300", [e[0] for e in b.vscan(300, 76, 126, 6)], [e[0] for e in a.vscan(300, 76, 126, 6)])
show("pill colours (track, selected)", (b.sample(b.W - 30, 101), b.sample(40, 101)), (a.sample(a.W - 30, 101), a.sample(40, 101)))
show("pill labels cols", [c[:2] for c in b.cols(60, 92, b.W - 20, 110, 60)[0]][:1] + [c[:2] for c in b.cols(60, 92, b.W - 20, 110, 60)[0]][-1:],
     [c[:2] for c in a.cols(60, 92, a.W - 20, 110, 60)[0]][:1] + [c[:2] for c in a.cols(60, 92, a.W - 20, 110, 60)[0]][-1:])
show("separators at x=300", seps(b, 300, 130, 560), seps(a, 300, 130, 560))
show("left column rows x 18..54 (section labels + icons)", b.rows(18, 130, 54, 560, 40)[0], a.rows(18, 130, 54, 560, 40)[0])
show("text column rows x 54..300", b.rows(54, 130, 300, 560, 40)[0], a.rows(54, 130, 300, 560, 40)[0])
show("text column first x", b.bbox(54, 145, 300, 200, 40), a.bbox(54, 145, 300, 200, 40))
show("chevron row1", b.bbox(b.W - 34, 160, b.W - 12, 185, 12, bg=b.sample(b.W - 40, 158)), a.bbox(a.W - 34, 160, a.W - 12, 185, 12, bg=a.sample(a.W - 40, 158)))
for nm, s in (("board", b), ("app", a)):
    print(nm, "p98: section label", pct(s, 20, 140, 70, 155, 98), " name", pct(s, 56, 160, 200, 178, 98), " meta", pct(s, 56, 182, 200, 196, 98),
          " icon", pct(s, 20, 160, 46, 190, 98), " chevron peak", s.peak(s.W - 34, 160, s.W - 12, 185))

print("=================== C links")
b = Sheet("board", "board/board-links-3x.png", btop=200)
a = Sheet("app", "app/links.png", gname="links")
show("pill selected (right half) hscan y=101", [e[0] for e in b.hscan(101, 150, b.W, 6)][-4:], [e[0] for e in a.hscan(101, 150, a.W, 6)][-4:])
show("separators at x=300", seps(b, 300, 130, 300), seps(a, 300, 130, 300))
show("letter tiles: rows x 16..54", b.rows(16, 130, 54, 300, 6)[0], a.rows(16, 130, 54, 300, 6)[0])
show("letter tile 1 hscan", [e[0] for e in b.hscan(155, 0, 60, 6)][:2], [e[0] for e in a.hscan(155, 0, 60, 6)][:2])
show("text rows x 56..330", b.rows(56, 130, 330, 300, 40)[0], a.rows(56, 130, 330, 300, 40)[0])
show("text first x", b.bbox(56, 140, 330, 180, 40), a.bbox(56, 140, 330, 180, 40))
show("arrow row1 bbox", b.bbox(b.W - 40, 140, b.W - 10, 175, 12, bg=b.sample(b.W - 44, 140)), a.bbox(a.W - 40, 140, a.W - 10, 175, 12, bg=a.sample(a.W - 44, 140)))
for nm, s in (("board", b), ("app", a)):
    print(nm, "tile fill", s.sample(24, 146), " letter p98", pct(s, 28, 148, 44, 162, 98), " arrow peak", s.peak(s.W - 40, 140, s.W - 10, 175),
          " domain p98", pct(s, 62, 172, 140, 186, 98))
