# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Terminal (D) second pass: key row in isolation, glyph metrics, cursor, text colours."""
from lib import *

B = load("board/board-terminal-kb-3x.png")
A = load("app/terminal-fit.png")
W = load("app/terminal-wide.png")
K = load("app/terminal-keys-scrolled.png")
p = lambda v: round(v / 3, 2)

print("== key row container")
for name, img, x in (("board", B, 3), ("app", A, 3)):
    print(name, "vedges at x=1pt:", [(p(e[0]), e[1], e[2]) for e in vedges(img, x, img.shape[0] - 700, None, thr=3)][:8])

def keys(name, img, y0, y1):
    # key fills are brighter than the row bg; threshold vs row bg
    rowbg = img[y0 + 6, 3]
    m = np.abs(img[y0:y1] - rowbg).max(axis=2) > 12
    colany = m.any(axis=0)
    out = []
    for s, e in runs_of(colany):
        sub = m[:, s:e + 1]
        ys = np.where(sub.any(axis=1))[0]
        out.append((p(s), p(e + 1), p(e + 1 - s), p(ys.min() + y0), p(ys.max() + 1 + y0)))
    print(name, "row bg", rowbg.tolist())
    for o in out:
        print("   key x %.2f-%.2f w %.2f  y %.2f-%.2f h %.2f" % (o[0], o[1], o[2], o[3], o[4], o[4] - o[3]))
    return out

kb = keys("board", B, 1576, 1720)
ka = keys("app", A, 2476, 2620)
kk = keys("app-scrolled", K, 2476, 2620)

print("== key fill / label colours")
print("board key fill", B[1640, 40].tolist(), " app key fill", A[2540, 40].tolist())
# esc label bbox
for name, img, x0, x1, y0, y1 in (("board", B, 24, 156, 1594, 1716), ("app", A, 25, 156, 2494, 2614)):
    bb = bbox(img, x0 + 6, y0 + 6, x1 - 6, y1 - 6, thr=60)
    sub = img[bb[1]:bb[3], bb[0]:bb[2]]
    print(name, "esc label x", p(bb[0]), p(bb[2]), " y", p(bb[1]), p(bb[3]), " w", p(bb[2] - bb[0]), " h", p(bb[3] - bb[1]), " peak", sub.max(axis=(0, 1)).tolist())

print("== terminal glyph metrics")
for r in rows(B, 30, 800, 1160, 870, thr=40):
    print("board line1 ink y", p(r[0]), p(r[1]), " x", p(r[2]), p(r[3]))
for r in rows(B, 30, 1490, 1160, 1545, thr=40):
    print("board last line ink y", p(r[0]), p(r[1]), " x", p(r[2]), p(r[3]))
# board 'M ios' line: capital M
for c in cols(B, 30, 910, 120, 970, thr=40)[:3]:
    print("   board 'M' x", p(c[0]), p(c[1]), " y", p(c[2]), p(c[3]))
# board digits '42 pass' line (y 444.4..461.8)
for c in cols(B, 30, 1333, 200, 1385, thr=40)[:4]:
    print("   board '42 pass' glyph x", p(c[0]), p(c[1]), " y", p(c[2]), p(c[3]))
for c in cols(A, 30, 370, 220, 420, thr=40)[:8]:
    print("   app 'sh-3.2$' glyph x", p(c[0]), p(c[1]), " y", p(c[2]), p(c[3]))
print("text peak colour board line 'bun test' grey", B[1270:1300, 110:300].max(axis=(0, 1)).tolist(), " board 0 fail", B[1385:1410, 150:300].max(axis=(0, 1)).tolist())
print("text peak colour app prompt", A[375:415, 36:200].max(axis=(0, 1)).tolist())

print("== cursor")
for name, img in (("fit", A), ("wide", W)):
    bb = bbox(img, 215, 360, 300, 440, thr=8, bg=[10, 10, 12])
    print(name, "cursor x", p(bb[0]), p(bb[2]), " y", p(bb[1]), p(bb[3]), " w", p(bb[2] - bb[0]), " h", p(bb[3] - bb[1]), " centre colour", img[(bb[1] + bb[3]) // 2, (bb[0] + bb[2]) // 2].tolist())
bb = bbox(B, 395, 1480, 440, 1545, thr=60, bg=[11, 11, 13])
print("board cursor x", p(bb[0]), p(bb[2]), " y", p(bb[1]), p(bb[3]), " w", p(bb[2] - bb[0]), " h", p(bb[3] - bb[1]))

print("== Fit/Wide labels and track")
for name, img, off, x0 in (("board", B, 54, 858), ("app", A, 62, 894)):
    y0 = int((off + 10) * 3); y1 = int((off + 42) * 3)
    print(name, "track fill sample (gap right end)", img[(y0 + y1) // 2, x0 + 270].tolist(), " white seg", img[y0 + 12, x0 + 30].tolist())
    for c in cols(img, x0 + 6, y0 + 10, x0 + 270, y1 - 10, thr=60, bg=None):
        print("   label col x", p(c[0]), p(c[1]), " y rel", p(c[2]) - off, p(c[3]) - off)
