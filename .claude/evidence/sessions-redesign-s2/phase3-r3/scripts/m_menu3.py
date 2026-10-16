# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""A third pass: chevrons vs card fill, pencil button, badge digit colour, tile label colour."""
import numpy as np
from sheet import Sheet

b = Sheet("board", "board/board-menu-appvalues-3x.png", btop=112)
a = Sheet("app", "app/menu.png", gname="menu")


def pct(s, x0, y0, x1, y1, q, floor=60):
    X0, Y0, X1, Y1 = s.box(x0, y0, x1, y1)
    g = s.a[Y0:Y1, X0:X1].max(axis=2).reshape(-1)
    g = g[g > floor]
    return round(float(np.percentile(g, q)), 1)


for nm, s in (("board", b), ("app", a)):
    for row, (y0, y1) in (("Model", (284, 308)), ("Host", (376, 400))):
        card = s.sample(s.W - 26, y0 + 2)
        bb = s.bbox(s.W - 44, y0, s.W - 28, y1, 10, bg=card)
        X0, Y0, X1, Y1 = s.box(s.W - 44, y0, s.W - 28, y1)
        pk = int(s.a[Y0:Y1, X0:X1].max())
        print(nm, row, "card", card, " chevron bbox", bb, " size", (round(bb[2] - bb[0], 2), round(bb[3] - bb[1], 2)),
              " right inset", round(s.W - bb[2], 2), " centre y", round((bb[1] + bb[3]) / 2, 2), " peak", pk)
    # pencil: find button by vscan near title end
    print(nm, "pencil vscan at centre:", [e[0] for e in s.vscan(268 if nm == "board" else 251, 12, 58, 6)][:1], [e[0] for e in s.vscan(268 if nm == "board" else 251, 12, 58, 6)][-1:])
    cx = 268 if nm == "board" else 251
    print(nm, "pencil fill", s.sample(cx - 10, 26), " glyph bbox", s.bbox(cx - 9, 27, cx + 9, 44, 60, bg=s.sample(cx - 10, 26)),
          " glyph peak", s.peak(cx - 9, 27, cx + 9, 44))
    h = s.hscan(26, cx - 25, cx + 25, 6)
    print(nm, "pencil hscan y=26", [e[0] for e in h][:1], [e[0] for e in h][-1:])
    print(nm, "badge digit p98", pct(s, s.W - 46, 108, s.W - 26, 124, 98), " tile label p98", pct(s, 28, 150, 84, 162, 98),
          " Fork p98", pct(s, 61, 421, 150, 437, 98))
