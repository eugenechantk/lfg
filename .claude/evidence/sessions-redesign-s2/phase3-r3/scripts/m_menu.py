# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""A (session sheet) measurements in sheet pt. Board sheet top 112; app geom 'menu'."""
from sheet import Sheet

b = Sheet("board", "board/board-menu-appvalues-3x.png", btop=112)
a = Sheet("app", "app/menu.png", gname="menu")


def show(title, rb, ra):
    print(f"-- {title}")
    print("   board:", rb)
    print("   app  :", ra)


print("== vertical structure at x=22 (tiles, cards, separators)")
show("vscan x=22", [e[0] for e in b.vscan(22, 60, 640, 6)], [e[0] for e in a.vscan(22, 60, 640, 6)])
print("== vertical structure at x=200 (separators, effort control)")
show("vscan x=200", [(e[0], e[2]) for e in b.vscan(200, 270, 600, 6)], [(e[0], e[2]) for e in a.vscan(200, 270, 600, 6)])

print("== header")
show("title+subtitle rows (x 18..250)", b.rows(18, 15, 250, 92, 40)[0], a.rows(18, 15, 250, 92, 40)[0])
show("pencil btn bbox", b.bbox(240, 15, 300, 55, 8), a.bbox(240, 15, 300, 55, 8))
show("pencil glyph bbox", b.bbox(262, 27, 276, 44, 60), a.bbox(262, 27, 276, 44, 60))
show("title ink x-extent (x 18..250, y 24..46)", b.bbox(18, 24, 250, 46, 60), a.bbox(18, 24, 250, 46, 60))
show("close btn bbox (right region)", b.bbox(b.W - 60, 15, b.W - 4, 62, 8), a.bbox(a.W - 60, 15, a.W - 4, 62, 8))
bc, ac = b.bbox(b.W - 60, 15, b.W - 4, 62, 8), a.bbox(a.W - 60, 15, a.W - 4, 62, 8)
print("   right inset board", round(b.W - bc[2], 2), " app", round(a.W - ac[2], 2))
show("close glyph", b.bbox(b.W - 45, 27, b.W - 25, 50, 80), a.bbox(a.W - 45, 27, a.W - 25, 50, 80))

print("== tiles")
for r, (y0, y1) in enumerate(((96, 174), (182, 260))):
    for c in range(3):
        bx0 = 16 + c * 122; ax0 = 16 + c * 126
        show(f"tile r{r} c{c} bbox", b.bbox(bx0 - 4, y0 - 4, bx0 + 118, y1 + 4, 6), a.bbox(ax0 - 4, y0 - 4, ax0 + 122, y1 + 4, 6))
        show(f"   icon bbox", b.bbox(bx0 + 6, y0 + 4, bx0 + 40, y0 + 36, 40), a.bbox(ax0 + 6, y0 + 4, ax0 + 40, y0 + 36, 40))
        show(f"   label rows", b.rows(bx0 + 6, y0 + 38, bx0 + 100, y1 - 2, 40)[0], a.rows(ax0 + 6, y0 + 38, ax0 + 104, y1 - 2, 40)[0])
        if r == 0 and c > 0:
            show(f"   badge bbox", b.bbox(bx0 + 80, y0 + 4, bx0 + 112, y0 + 36, 8), a.bbox(ax0 + 84, y0 + 4, ax0 + 116, y0 + 36, 8))

print("== card 1 rows")
labels = [("Model", 274, 317), ("Effort", 317, 366), ("Host", 366, 409), ("Fork", 409, 452), ("Mark", 452, 494)]
for name, y0, y1 in labels:
    show(f"{name} left cols (x 24..170)", b.cols(24, y0 + 3, 170, y1 - 3, 40)[0][:3], a.cols(24, y0 + 3, 170, y1 - 3, 40)[0][:3])
    show(f"{name} left rows", b.rows(24, y0 + 3, 150, y1 - 3, 40)[0], a.rows(24, y0 + 3, 150, y1 - 3, 40)[0])
show("Model right side cols", b.cols(200, 280, b.W - 18, 312, 30)[0], a.cols(200, 280, a.W - 18, 312, 30)[0])
show("Host right side cols", b.cols(140, 372, b.W - 18, 404, 30)[0][-3:], a.cols(140, 372, a.W - 18, 404, 30)[0][-3:])
show("Host value bbox", b.bbox(140, 372, b.W - 34, 404, 40), a.bbox(140, 372, a.W - 34, 404, 40))
show("chevron Model", b.bbox(b.W - 34, 284, b.W - 18, 308, 12), a.bbox(a.W - 34, 284, a.W - 18, 308, 12))
show("chevron Host", b.bbox(b.W - 34, 376, b.W - 18, 400, 12), a.bbox(a.W - 34, 376, a.W - 18, 400, 12))
show("effort track hscan y=341", [(e[0]) for e in b.hscan(341, 140, b.W - 4, 6)][:3] + [(e[0]) for e in b.hscan(341, 140, b.W - 4, 6)][-3:],
     [(e[0]) for e in a.hscan(341, 140, a.W - 4, 6)][:3] + [(e[0]) for e in a.hscan(341, 140, a.W - 4, 6)][-3:])
show("effort track vscan x=150/162", [e[0] for e in b.vscan(b.W - 30, 318, 365, 6)], [e[0] for e in a.vscan(a.W - 30, 318, 365, 6)])

print("== card 2 + footer")
for name, y0, y1 in (("Stop", 508, 551), ("End", 551, 593)):
    show(f"{name} cols", b.cols(24, y0 + 3, 200, y1 - 3, 40)[0][:3], a.cols(24, y0 + 3, 200, y1 - 3, 40)[0][:3])
    show(f"{name} rows", b.rows(24, y0 + 3, 200, y1 - 3, 40)[0], a.rows(24, y0 + 3, 200, y1 - 3, 40)[0])
show("footer rows", b.rows(10, 598, b.W - 10, 640, 30)[0], a.rows(10, 598, a.W - 10, 640, 30)[0])
fb, fa = b.rows(10, 598, b.W - 10, 640, 30)[0][0], a.rows(10, 598, a.W - 10, 640, 30)[0][0]
print("   footer centre board", round((fb[2] + fb[3]) / 2, 2), "of", b.W / 2, " app", round((fa[2] + fa[3]) / 2, 2), "of", a.W / 2,
      " width board", round(fb[3] - fb[2], 2), " app", round(fa[3] - fa[2], 2))

print("== colours (sample / peak)")
for nm, (x, y) in {"sheet bg": (200, 630), "tile fill": (60, 120), "card fill": (200, 300), "close fill": (None, 30),
                    "pencil fill": (None, 35)}.items():
    if x is None:
        bx = b.W - 22 if nm == "close fill" else 258
        ax = a.W - 22 if nm == "close fill" else None
        if ax is None:
            pb = b.bbox(240, 15, 300, 55, 8); pa = a.bbox(240, 15, 300, 55, 8)
            print(f"   {nm}: board", b.sample(pb[0] + 3, 35), " app", a.sample(pa[0] + 3, 35))
            continue
        print(f"   {nm}: board", b.sample(bx, 30), " app", a.sample(ax, 30))
        continue
    print(f"   {nm}: board", b.sample(x, y), " app", a.sample(x, y))
print("   subtitle peak: board", b.peak(20, 55, 150, 68), " app", a.peak(20, 55, 150, 68))
print("   tile icon peak (blue): board", b.peak(28, 106, 50, 128), " app", a.peak(28, 106, 50, 128))
print("   Fork label peak: board", b.peak(60, 420, 140, 440), " app", a.peak(60, 420, 140, 440))
print("   End label peak: board", b.peak(60, 562, 140, 582), " app", a.peak(60, 562, 140, 582))
print("   Opus value peak: board", b.peak(260, 285, 320, 305), " app", a.peak(272, 285, 332, 305))
print("   C badge: board", b.sample(245, 294), " app", a.sample(253, 294))
print("   footer peak: board", b.peak(30, 606, 200, 622), " app", a.peak(30, 606, 200, 622))
print("   effort selected: board", b.sample(270, 334), " app", a.sample(a.W - 102, 334), " track: board", b.sample(b.W - 20, 334), " app", a.sample(a.W - 20, 334))
print("   browser tile dimmed icon peak: board", b.peak(150, 192, 175, 215), " app", a.peak(154, 192, 179, 215))
