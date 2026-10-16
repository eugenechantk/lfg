# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""C follow-up: file-row chevrons and link-tile fill."""
from sheet import Sheet

b = Sheet("board", "board/board-files-3x.png", btop=200)
a = Sheet("app", "app/files.png", gname="files")
for nm, s in (("board", b), ("app", a)):
    for y0, y1 in ((180, 205), (240, 262), (328, 350), (416, 438), (474, 496)):
        bb = s.bbox(s.W - 34, y0, s.W - 12, y1, 12, bg=s.sample(s.W - 40, y0))
        X0, Y0, X1, Y1 = s.box(s.W - 34, y0, s.W - 12, y1)
        print(nm, "chevron", bb, " size", round(bb[2] - bb[0], 2), round(bb[3] - bb[1], 2), " right inset", round(s.W - bb[2], 2),
              " centre y", round((bb[1] + bb[3]) / 2, 2), " peak", int(s.a[Y0:Y1, X0:X1].max()))
b = Sheet("board", "board/board-links-3x.png", btop=200)
a = Sheet("app", "app/links.png", gname="links")
for nm, s in (("board", b), ("app", a)):
    print(nm, "link tile fill", s.sample(23, 150), s.sample(47, 175), " tile corner radius probe hscan y=147.8:", [e[0] for e in s.hscan(147.8, 15, 55, 6)][:2])
