# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""A second pass: header row hscan, badge insets, chevrons, grey-text percentiles."""
import numpy as np
from sheet import Sheet

b = Sheet("board", "board/board-menu-appvalues-3x.png", btop=112)
a = Sheet("app", "app/menu.png", gname="menu")


def pct(s, x0, y0, x1, y1, q, floor=60):
    X0, Y0, X1, Y1 = s.box(x0, y0, x1, y1)
    g = s.a[Y0:Y1, X0:X1].max(axis=2).reshape(-1)
    g = g[g > floor]
    return round(float(np.percentile(g, q)), 1)


print("== header row: title ink cols then pencil button (y 26..44)")
for nm, s in (("board", b), ("app", a)):
    cs, bg = s.cols(18, 26, 300, 44, 40)
    print(nm, "first", cs[0][:2], " last title glyph", [c[:2] for c in cs if c[0] < 235][-1])
    print(nm, "pencil btn hscan y=35:", [(e[0], e[2]) for e in s.hscan(35, 200, 300, 6)][:2], "...", [(e[0], e[2]) for e in s.hscan(35, 200, 300, 6)][-2:])
    print(nm, "pencil btn vscan:", [(e[0], e[2]) for e in s.vscan([268, 255][0] if nm == "board" else 0, 0, 0)][:0])
print("board pencil vscan x=268:", [(e[0]) for e in b.vscan(268, 12, 58, 6)])
# app pencil centre: find from hscan
he = a.hscan(35, 200, 300, 6)
xs = [e[0] for e in he if e[2][0] > 50 and e[1][0] < 35]
print("app hscan y=35 transitions into fill:", [(e[0], e[1], e[2]) for e in he][:6])
print("== close button")
for nm, s in (("board", b), ("app", a)):
    print(nm, "close hscan y=38:", [(e[0], e[2]) for e in s.hscan(38, s.W - 60, s.W - 1, 6)][:1], [(e[0], e[2]) for e in s.hscan(38, s.W - 60, s.W - 1, 6)][-1:])
    print(nm, "close vscan x=W-34:", [e[0] for e in s.vscan(s.W - 34, 10, 62, 6)][:1], [e[0] for e in s.vscan(s.W - 34, 10, 62, 6)][-1:])

print("== badges (hscan at badge centre y=116, vscan at badge centre)")
for nm, s, c1r, c2r in (("board", b, 252, 374), ("app", a, 260, 386)):
    for tr in (c1r, c2r):
        h = s.hscan(116, tr - 40, tr + 1, 8)
        print(nm, f"tile right {tr}: badge x-transitions", [e[0] for e in h][:1], [e[0] for e in h][-2:], " inset", round(tr - [e[0] for e in h if e[0] < tr - 2][-1], 2))
    v = s.vscan(c2r - 20, 96, 140, 8)
    print(nm, "badge2 vscan", [e[0] for e in v])
    print(nm, "badge fill", s.sample(c2r - 13, 116), " digit peak", s.peak(c2r - 25, 108, c2r - 12, 124))

print("== chevrons (Model row 274-317, Host row 366-409)")
for nm, s in (("board", b), ("app", a)):
    for row, (y0, y1) in (("Model", (282, 310)), ("Host", (374, 402))):
        bb = s.bbox(s.W - 30, y0, s.W - 12, y1, 12, bg=s.sample(s.W - 14, y0))
        pk = s.peak(s.W - 30, y0, s.W - 12, y1)
        print(nm, row, "chevron bbox", bb, " size", (round(bb[2] - bb[0], 2), round(bb[3] - bb[1], 2)) if bb else None,
              " right inset", round(s.W - bb[2], 2) if bb else None, " peak", pk)

print("== grey text (p90 / p98 of glyph pixels) vs white reference")
for nm, s, ox in (("board", b, 0), ("app", a, 12)):
    print(nm, "subtitle p90/p98", pct(s, 20, 55, 240, 69, 90), pct(s, 20, 55, 240, 69, 98),
          " Opus p90/p98", pct(s, 262 + ox, 286, 338 + ox, 303, 90), pct(s, 262 + ox, 286, 338 + ox, 303, 98),
          " Host value p90", pct(s, 155 + ox, 380, 338 + ox, 396, 90),
          " footer p90/p98", pct(s, 36, 606, 360, 622, 90), pct(s, 36, 606, 360, 622, 98),
          " title p98 (white ref)", pct(s, 22, 26, 200, 43, 98),
          " Model label p98", pct(s, 33, 288, 80, 302, 98))
