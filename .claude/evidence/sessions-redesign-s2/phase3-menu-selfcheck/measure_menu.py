"""Session sheet self-check: board `s2-menu` vs the app frame, per element.

  python3 measure_menu.py <app-png> <app-sheet-top> [scale]

The app draws a partial-height sheet at ~0.96 scale (iOS 26 inset sheet). Every
app position is converted back to unscaled sheet coordinates before comparing:
  y_rel = (y_app - sheet_top) / scale,  x_unscaled = 201 + (x_app - 201) / scale.
Board positions are relative to its sheet top (112). Values in points.
"""
import sys
from PIL import Image

S = 3
SNAPS = "/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad/snaps/"
board = Image.open(SNAPS + "board-s2-menu.png").convert("RGB")
app = Image.open(sys.argv[1]).convert("RGB")
top = float(sys.argv[2])
scale = float(sys.argv[3]) if len(sys.argv) > 3 else 386 / 402
BTOP = 112.0


def rows_matching(img, x0, x1, y0, y1, pred):
    ys = []
    for yy in range(int(y0 * S), int(y1 * S)):
        for xx in range(int(x0 * S), int(x1 * S)):
            if pred(img.getpixel((xx, yy))):
                ys.append(yy)
                break
    return (min(ys) / S, (max(ys) + 1) / S) if ys else (None, None)


def app_box(bx0, bx1, by0, by1, right_anchored=False):
    """Board box (390-wide, absolute) -> app apparent box."""
    def ax(x):
        if right_anchored:
            x = 402 - (390 - x)
        return 201 + (x - 201) * scale
    def ay(y):
        return top + (y - BTOP) * scale
    return ax(bx0), ax(bx1), ay(by0), ay(by1)


def bright(p):
    return sum(p) / 3 > 140


def blue(p):
    return p[2] > 180 and p[0] < 120


def red(p):
    return p[0] > 200 and p[1] < 120


def purple(p):
    return p[0] > 150 and p[2] > 200 and p[1] < 120


def chrome(p):  # #3A3A3C-ish fills
    return 52 <= p[0] <= 64 and 52 <= p[1] <= 64


checks = [
    # name, board box (x0, x1, y0, y1), predicate, right-anchored
    ("title glyphs", (20, 240, 128, 166), bright, False),
    ("pencil button", (250, 287, 128, 166), chrome, False),
    ("close button", (334, 378, 126, 172), chrome, True),
    ("subtitle glyphs", (20, 240, 163, 185), lambda p: 110 < sum(p) / 3 < 200, False),
    ("terminal icon", (26, 52, 214, 244), blue, False),
    ("Terminal label", (26, 120, 256, 284), bright, False),
    ("Files badge", (215, 247, 212, 244), chrome, False),
    ("Browser preview label", (148, 240, 324, 368), bright, False),
    ("Model glyphs", (28, 100, 392, 424), bright, False),
    ("Claude mark", (232, 260, 392, 424), lambda p: p[0] > 150 and p[1] < 110, True),
    ("effort control", (154, 362, 432, 474), chrome, True),
    ("selected segment", (260, 305, 436, 470), lambda p: 92 <= p[0] <= 106, True),
    ("Host glyphs", (28, 100, 482, 516), bright, False),
    ("fork icon", (28, 54, 528, 556), blue, False),
    ("Fork session glyphs", (58, 200, 526, 558), blue, False),
    ("unread dot", (30, 52, 570, 596), purple, False),
    ("Stop square", (30, 52, 628, 656), bright, False),
    ("Stop current turn glyphs", (58, 250, 624, 658), bright, False),
    ("End icon", (28, 54, 668, 700), red, False),
    ("footer glyphs", (30, 360, 714, 742), lambda p: 110 < sum(p) / 3 < 200, False),
]

print(f"{'element':28} {'board top':>9} {'app top':>8} {'d':>6}   {'board h':>7} {'app h':>6} {'d':>6}")
for name, (x0, x1, y0, y1), pred, right in checks:
    bt, bb = rows_matching(board, x0, x1, y0, y1, pred)
    ax0, ax1, ay0, ay1 = app_box(x0, x1, y0, y1, right)
    at, ab = rows_matching(app, ax0, ax1, ay0 - 2, ay1 + 2, pred)
    if bt is None or at is None:
        print(f"{name:28} board {bt} app {at}")
        continue
    b_rel, b_h = bt - BTOP, bb - bt
    a_rel, a_h = (at - top) / scale, (ab - at) / scale
    print(f"{name:28} {b_rel:9.2f} {a_rel:8.2f} {a_rel - b_rel:+6.2f}   {b_h:7.2f} {a_h:6.2f} {a_h - b_h:+6.2f}")
