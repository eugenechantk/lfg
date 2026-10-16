# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""E (sign-in browser chrome). Board 390x844 render (sheet top 54); app frame 402x874 3x.
Top chrome compared relative to the sheet top; bottom bar relative to the screen bottom."""
import numpy as np
from lib import load, bbox, rows, cols, vedges, hedges

B = load("board/board-signin-appvalues-3x.png")
A = load("app/signin.png")
p = lambda v: round(v / 3, 2)


def pct(img, x0, y0, x1, y1, q, floor=60):
    g = img[int(y0 * 3):int(y1 * 3), int(x0 * 3):int(x1 * 3)].max(axis=2).reshape(-1)
    g = g[g > floor]
    return round(float(np.percentile(g, q)), 1) if len(g) else None


for nm, img in (("board", B), ("app", A)):
    H = img.shape[0] / 3; W = img.shape[1] / 3
    ve = vedges(img, int(200 * 3), 0, int(140 * 3), 4)
    print(nm, "vedges x=200 (0..140pt):", [(p(e[0]), e[2]) for e in ve])
    ve2 = vedges(img, int(30 * 3), 0, int(140 * 3), 4)
    print(nm, "vedges x=30 (0..140pt):", [(p(e[0]), e[2]) for e in ve2])
print()
# sheet top: first row where column x=200 turns from black to the sheet colour
def sheet_top(img):
    col = img[:, 600]
    for y in range(60, 600):
        if col[y].max() > 20 and col[y + 3].max() > 20:
            return y / 3
BT, AT = sheet_top(B), sheet_top(A)
print("sheet top pt: board", BT, " app", AT)

for nm, img, T in (("board", B, BT), ("app", A, AT)):
    W = img.shape[1] / 3; H = img.shape[0] / 3
    y0, y1 = int((T + 5) * 3), int((T + 60) * 3)
    # close button
    he = hedges(img, int((T + 33) * 3), 0, int(W * 3), 6)
    print(nm, "top bar hscan at rel 33:", [p(e[0]) for e in he][:6], "...", [p(e[0]) for e in he][-6:])
    vb = vedges(img, int(30 * 3), y0, y1, 6)
    print(nm, "close vscan x=30 rel:", [round(p(e[0]) - T, 2) for e in vb])
    vb = vedges(img, int(W - 30) * 3, y0, y1, 6)
    print(nm, "reload vscan x=W-30 rel:", [round(p(e[0]) - T, 2) for e in vb])
    vb = vedges(img, int(100 * 3), y0, y1, 6)
    print(nm, "url pill vscan x=100 rel:", [round(p(e[0]) - T, 2) for e in vb])
    print(nm, "fills: close", img[int((T + 20) * 3), 90].tolist(), " url", img[int((T + 20) * 3), 300].tolist(), " bar bg", img[int((T + 5) * 3), 600].tolist(),
          " sheet", img[int((T + 59) * 3), 600].tolist())
    # url text rows (x 60..W-62)
    r = rows(img, int(62 * 3), int((T + 15) * 3), int((W - 62) * 3), int((T + 51) * 3), 40, bg=img[int((T + 20) * 3), 300])
    print(nm, "url text rows rel:", [(round(p(a) - T, 2), round(p(b) - T, 2), p(c), p(d), round((p(c) + p(d)) / 2, 2)) for a, b, c, d in r])
    print(nm, "  host p98", pct(img, 100, T + 17, W - 100, T + 32, 98), " subtitle peak", img[int((T + 34) * 3):int((T + 48) * 3), int(80 * 3):int((W - 80) * 3)].reshape(-1, 3)[
        img[int((T + 34) * 3):int((T + 48) * 3), int(80 * 3):int((W - 80) * 3)].reshape(-1, 3).sum(axis=1).argmax()].tolist())
    gl = bbox(img, int(16 * 3), int((T + 22) * 3), int(44 * 3), int((T + 44) * 3), 60, bg=img[int((T + 20) * 3), 90])
    print(nm, "  close glyph", (p(gl[0]), round(p(gl[1]) - T, 2), p(gl[2]), round(p(gl[3]) - T, 2)), " size", p(gl[2] - gl[0]), p(gl[3] - gl[1]),
          " peak", img[gl[1]:gl[3], gl[0]:gl[2]].max())
    gr = bbox(img, int((W - 44) * 3), int((T + 22) * 3), int((W - 16) * 3), int((T + 44) * 3), 60, bg=img[int((T + 20) * 3), int((W - 30) * 3) - 30])
    print(nm, "  reload glyph", (p(gr[0]), round(p(gr[1]) - T, 2), p(gr[2]), round(p(gr[3]) - T, 2)), " size", p(gr[2] - gr[0]), p(gr[3] - gr[1]),
          " right inset", round(W - p(gr[2]), 2), " peak", img[gr[1]:gr[3], gr[0]:gr[2]].max())
    lk = bbox(img, int(100 * 3), int((T + 17) * 3), int(160 * 3), int((T + 33) * 3), 40, bg=img[int((T + 20) * 3), 300])
    print(nm, "  lock+host first glyph bbox", (p(lk[0]), round(p(lk[1]) - T, 2), p(lk[2]), round(p(lk[3]) - T, 2)))
    lcols = cols(img, int(100 * 3), int((T + 17) * 3), int((W - 100) * 3), int((T + 33) * 3), 40, bg=img[int((T + 20) * 3), 300])
    print(nm, "  host cols first 3:", [(p(c[0]), p(c[1]), round(p(c[2]) - T, 2), round(p(c[3]) - T, 2)) for c in lcols[:3]])
    print()
    # web content area
    vc = vedges(img, int(200 * 3), int((T + 50) * 3), int((T + 80) * 3), 10)
    print(nm, "web top edge rel:", [round(p(e[0]) - T, 2) for e in vc][:3])
    vc = vedges(img, int(5 * 3), int((H - 140) * 3), int(H * 3) - 1, 6)
    print(nm, "bottom region vscan x=5 (from bottom):", [(round(H - p(e[0]), 2), e[2]) for e in vc])
    vc = vedges(img, int(32 * 3), int((H - 140) * 3), int(H * 3) - 1, 6)
    print(nm, "back btn vscan x=32 (from bottom):", [round(H - p(e[0]), 2) for e in vc])
    he = hedges(img, int((H - 56) * 3), 0, int(W * 3), 6)
    print(nm, "bottom bar hscan at H-56:", [p(e[0]) for e in he])
    vc = vedges(img, int(250 * 3), int((H - 140) * 3), int(H * 3) - 1, 6)
    print(nm, "primary btn vscan x=250 (from bottom):", [round(H - p(e[0]), 2) for e in vc])
    print(nm, "fills: back", img[int((H - 56) * 3), int(16 * 3)].tolist(), " fwd", img[int((H - 56) * 3), int(68 * 3)].tolist(),
          " primary", img[int((H - 66) * 3), int(200 * 3)].tolist(), " bar", img[int((H - 10) * 3), int(200 * 3)].tolist())
    bk = bbox(img, int(22 * 3), int((H - 70) * 3), int(44 * 3), int((H - 42) * 3), 20, bg=img[int((H - 56) * 3), int(16 * 3)])
    fw = bbox(img, int(74 * 3), int((H - 70) * 3), int(96 * 3), int((H - 42) * 3), 20, bg=img[int((H - 56) * 3), int(68 * 3)])
    print(nm, "  back chevron", (p(bk[0]), p(bk[2]), round(H - p(bk[1]), 2), round(H - p(bk[3]), 2)), " peak", img[bk[1]:bk[3], bk[0]:bk[2]].max(),
          "| fwd chevron", (p(fw[0]), p(fw[2]), round(H - p(fw[1]), 2), round(H - p(fw[3]), 2)), " peak", img[fw[1]:fw[3], fw[0]:fw[2]].max())
    lb = rows(img, int(130 * 3), int((H - 75) * 3), int((W - 20) * 3), int((H - 40) * 3), 60, bg=img[int((H - 66) * 3), int(200 * 3)])
    print(nm, "  primary label rows (from bottom)", [(round(H - p(a), 2), round(H - p(b), 2), p(c), p(d), round((p(c) + p(d)) / 2, 2)) for a, b, c, d in lb],
          " p98", pct(img, 130, H - 75, W - 20, H - 40, 98))
    print()
