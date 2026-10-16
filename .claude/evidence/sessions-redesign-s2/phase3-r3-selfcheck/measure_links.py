"""Links tab self-check: board `s2-files` Links state (DOM spec) vs the app frame.

  python3 measure_links.py <app-png>

The board has no 3x render of this state, so the board side is the DOM spec
(specs/s2-files-links.txt), sheet top 200. The app sheet is inset and scaled
(~0.9602); app positions are converted back to unscaled sheet coordinates:
  y = (y_app - sheet_top) / s,  x = (x_app - sheet_left) / s.
"""
import sys
from PIL import Image

S = 3
app = Image.open(sys.argv[1]).convert("RGB")
W, H = app.size


def px(x, y):
    return app.getpixel((int(x * S), int(y * S)))


# Sheet edges from the surface colour (#1C1C1E, app ~ (26..30)).
def is_surface(p):
    return 24 <= p[0] <= 31 and 24 <= p[1] <= 31 and 26 <= p[2] <= 33


mid_y = 600
left = next(x / S for x in range(0, W // 2) if is_surface(app.getpixel((x, mid_y * S))))
right = next(x / S for x in range(W - 1, W // 2, -1) if is_surface(app.getpixel((x, mid_y * S)))) + 1 / S
s = (right - left) / 390 * (390 / 390)
s = (right - left) / 402 * (402 / 390) if False else (right - left) / 390
# The board sheet is 390 wide; the app sheet is the device width (402) scaled.
s_app = (right - left) / 402
top = next(y / S for y in range(150 * S, 300 * S) if is_surface(app.getpixel((int(200 * S), y))))
print(f"sheet left {left:.2f} right {right:.2f} top {top:.2f} scale {s_app:.4f}")


def to_sheet(x, y):
    return (x - left) / s_app, (y - top) / s_app


def ink_box(x0, x1, y0, y1, pred):
    xs, ys = [], []
    for yy in range(int(y0 * S), int(y1 * S)):
        for xx in range(int(x0 * S), int(x1 * S)):
            if pred(app.getpixel((xx, yy))):
                xs.append(xx)
                ys.append(yy)
    if not xs:
        return None
    a = to_sheet(min(xs) / S, min(ys) / S)
    b = to_sheet((max(xs) + 1) / S, (max(ys) + 1) / S)
    return a[0], a[1], b[0], b[1]


def app_region(sx0, sx1, sy0, sy1, right_anchored=False):
    # sheet coords (board, 390 wide) -> app screen coords; right-anchored items
    # keep their distance from the right edge (app sheet is 402 wide unscaled).
    if right_anchored:
        sx0, sx1 = sx0 + 12, sx1 + 12
    return left + sx0 * s_app, left + sx1 * s_app, top + sy0 * s_app, top + sy1 * s_app


tile = lambda p: 38 <= p[0] <= 48 and 38 <= p[1] <= 48 and abs(p[0] - p[2]) <= 4
letter = lambda p: p[0] > 150
white = lambda p: p[0] > 200 and p[1] > 200
grey = lambda p: 120 < p[0] < 185 and abs(p[0] - p[2]) < 12
arrow = lambda p: 80 <= p[0] <= 110 and abs(p[0] - p[2]) < 8
sep = lambda p: 45 <= p[0] <= 62 and abs(p[0] - p[2]) <= 4

# (name, board box in sheet coords (x0,y0,x1,y1) from the spec, search region, predicate, right)
B = 200
rows = [
    ("row1 tile", (20, 347.5 - B, 50, 377.5 - B), (14, 56, 140, 186), tile, False),
    ("row1 'G' ink", (29.7, 354.5 - B, 40.4, 370.5 - B), (24, 46, 150, 176), letter, False),
    ("row1 title ink", (62, 344 - B, 318.8, 364 - B), (58, 340, 140, 164), white, False),
    ("row1 domain ink", (62, 366 - B, 130.8, 381 - B), (58, 200, 164, 184), grey, False),
    ("row1 arrow", (359, 354.5 - B, 374, 369.5 - B), (352, 380, 148, 176), arrow, True),
    ("row1 separator", (62, 392.5 - B, 390, 393 - B), (58, 120, 188, 197), sep, False),
    ("row2 tile", (20, 408.5 - B, 50, 438.5 - B), (14, 56, 201, 247), tile, False),
    ("row2 title ink", (62, 405 - B, 220.9, 425 - B), (58, 340, 201, 225), white, False),
    ("row2 domain ink", (62, 427 - B, 233.5, 442 - B), (58, 280, 225, 245), grey, False),
    ("row2 arrow", (359, 415.5 - B, 374, 430.5 - B), (352, 380, 209, 237), arrow, True),
    ("row2 separator", (62, 453.5 - B, 390, 454 - B), (58, 120, 249, 258), sep, False),
]
print(f"{'element':18} {'board x0,y0 -> x1,y1':>34}   {'app x0,y0 -> x1,y1':>34}")
for name, bbox, reg, pred, right in rows:
    ax0, ax1, ay0, ay1 = app_region(*reg, right_anchored=right)
    got = ink_box(ax0, ax1, ay0, ay1, pred)
    if got and right:
        got = (got[0] - 12, got[1], got[2] - 12, got[3])
    bs = f"{bbox[0]:6.1f},{bbox[1]:6.1f} -> {bbox[2]:6.1f},{bbox[3]:6.1f}"
    gs = "none" if not got else f"{got[0]:6.1f},{got[1]:6.1f} -> {got[2]:6.1f},{got[3]:6.1f}"
    print(f"{name:18} {bs:>34}   {gs:>34}")
