# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Terminal (D) measurements. Board: board/board-terminal-kb-3x.png (390x844 pt, top inset 54).
App: app/terminal-fit.png, app/terminal-wide.png, app/terminal-keys-scrolled.png (402x874, inset 62).
All output in pt; 'rel' = relative to the page top under the status bar (board -54, app -62)."""
import sys
from lib import *

B = load("board/board-terminal-kb-3x.png")
A = load("app/terminal-fit.png")
W = load("app/terminal-wide.png")
K = load("app/terminal-keys-scrolled.png")
p = lambda v: round(v / 3, 2)

print("== colours (px samples)")
print("board page bg", B[700, 600].tolist(), " app page bg", A[1200, 600].tolist())
print("board close fill", B[240, 60].tolist(), " app close fill", A[264, 60].tolist())
print("board track", B[240, 1100].tolist(), " app track", A[264, 1150].tolist())

print("== header")
# close button: region left 0..200 px, rows 150..340 (board), 170..360 (app)
for name, img, y0, y1, off in (("board", B, 150, 330, 54), ("app", A, 175, 355, 62)):
    bb = bbox(img, 0, y0, 220, y1, thr=12)
    print(name, "close btn pt x", p(bb[0]), p(bb[2]), " y rel", p(bb[1]) - off, p(bb[3]) - off)
    g = bbox(img, bb[0] + 20, bb[1] + 20, bb[2] - 20, bb[3] - 20, thr=80)
    print(name, "  close glyph x", p(g[0]), p(g[2]), " y rel", p(g[1]) - off, p(g[3]) - off, " size", p(g[2] - g[0]), p(g[3] - g[1]))
    # title block between x 230..800 px
    for r in rows(img, 230, y0, 820, y1, thr=40):
        print(name, "  text row y rel", p(r[0]) - off, p(r[1]) - off, " x", p(r[2]), p(r[3]), " centre x", round((p(r[2]) + p(r[3])) / 2, 2))
    # track
    W0 = img.shape[1]
    tb = bbox(img, W0 - 380, y0, W0, y1, thr=12)
    print(name, "  track x", p(tb[0]), p(tb[2]), " right inset", round(W0 / 3 - p(tb[2]), 2), " y rel", p(tb[1]) - off, p(tb[3]) - off)
    sb = bbox(img, tb[0] + 3, tb[1] + 3, tb[2] - 3, tb[3] - 3, thr=150, bg=[11, 11, 13])
    # selected white segment: find bright fill
    m = (img[tb[1]:tb[3], tb[0]:tb[2]].min(axis=2) > 230)
    ys, xs = np.where(m)
    print(name, "  white seg x", p(xs.min() + tb[0]), p(xs.max() + tb[0] + 1), " y rel", p(ys.min() + tb[1]) - off, p(ys.max() + tb[1] + 1) - off)
    for c in cols(img, tb[0] + 6, tb[1] + 8, tb[2] - 6, tb[3] - 8, thr=60):
        pass

print("== terminal text")
# board: first mock line at y 270.5 pt. app: prompt row near 124 pt (abs)
for r in rows(A, 20, 360, 700, 440, thr=40):
    print("app row1 y abs", p(r[0]), p(r[1]), " rel", p(r[0]) - 62, p(r[1]) - 62, " x", p(r[2]), p(r[3]))
for c in cols(A, 20, 360, 700, 440, thr=40)[:12]:
    print("   app glyph x", p(c[0]), p(c[1]), " y", p(c[2]), p(c[3]))
# cursor (Wide frame is the bright one)
for name, img in (("fit", A), ("wide", W)):
    reg = img[360:440, 200:300]
    print(name, "cursor sample", img[395, 240].tolist())
    bb = bbox(img, 200, 360, 300, 440, thr=20, bg=[11, 11, 13])
    print(name, "cursor bbox x", p(bb[0]), p(bb[2]), " y abs", p(bb[1]), p(bb[3]), " w", p(bb[2] - bb[0]), " h", p(bb[3] - bb[1]))
# board cursor
bb = bbox(B, 380, 1480, 450, 1540, thr=60, bg=[11, 11, 13])
print("board cursor x", p(bb[0]), p(bb[2]), " y", p(bb[1]), p(bb[3]), " sample", B[1510, 412].tolist())
# board glyphs of first line 'eugene@Pro'
for r in rows(B, 20, 800, 1160, 840, thr=40):
    print("board line1 y", p(r[0]), p(r[1]), " x", p(r[2]), p(r[3]))
for c in cols(B, 20, 800, 1160, 840, thr=40)[:12]:
    print("   board glyph x", p(c[0]), p(c[1]), " y", p(c[2]), p(c[3]))

print("== status line (app)")
for name, img in (("fit", A), ("wide", W)):
    ve = [e for e in vedges(img, 600, 2300, 2520, thr=40)]
    print(name, "status vedges at x=600:", [(p(e[0]), e[2]) for e in ve])
    he = hedges(img, 2400, 0, 1206, thr=60)
    print(name, "status hedges first/last:", [(p(e[0]), e[2]) for e in he[:2]], [(p(e[0]), e[2]) for e in he[-2:]])
    cs = cols(img, 30, 2380, 1180, 2425, thr=60, bg=list(img[2400, 600]))
    print(name, "status glyph cols", len(cs), " first", [(p(c[0]), p(c[1])) for c in cs[:4]], " last", [(p(c[0]), p(c[1])) for c in cs[-3:]])
