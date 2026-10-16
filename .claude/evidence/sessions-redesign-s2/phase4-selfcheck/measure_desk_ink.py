"""Ink boxes for named regions, board vs window shot (both 1x)."""
from PIL import Image

S = "/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad/snaps/"
board = Image.open(S + "board-dA2-1x.png").convert("RGB")
import sys
app = Image.open(S + (sys.argv[1] if len(sys.argv) > 1 else "d2.png")).convert("RGB")


def ink(im, box, pred):
    x0, y0, x1, y1 = box
    xs, ys = [], []
    for y in range(y0, y1):
        for x in range(x0, x1):
            if pred(im.getpixel((x, y))):
                xs.append(x); ys.append(y)
    return (min(xs), min(ys), max(xs) + 1, max(ys) + 1) if xs else None


bright = lambda p: sum(p) / 3 > 150
amber = lambda p: p[0] > 180 and p[1] > 110 and p[2] < 110
green = lambda p: p[1] > 150 and p[0] < 130 and p[2] < 140
grey = lambda p: 110 < sum(p) / 3 < 200 and abs(p[0] - p[2]) < 15
regions = [
    ("Sessions label", (126, 14, 190, 38), bright),
    ("Sessions badge", (190, 14, 214, 38), amber),
    ("Tasks label", (228, 14, 270, 38), lambda p: sum(p) / 3 > 120 and abs(p[0] - p[2]) < 20),
    ("search glyph", (360, 13, 386, 39), bright),
    ("Pro dot", (14, 56, 25, 70), green),
    ("Pro label", (29, 54, 55, 72), grey),
    ("Air ring", (60, 56, 72, 70), amber),
    ("Air offline label", (75, 54, 135, 72), amber),
    ("3 working", (137, 54, 205, 72), grey),
    ("By status text", (310, 56, 366, 70), lambda p: sum(p) / 3 > 120),
    ("By status chevron", (366, 56, 380, 70), lambda p: sum(p) / 3 > 120),
    ("NI chevron", (16, 97, 31, 113), grey),
    ("NI title", (35, 95, 116, 117), amber),
    ("NI count", (119, 95, 131, 117), grey),
    ("row1 time", (14, 128, 50, 150), amber),
    ("row1 ago", (14, 150, 40, 166), grey),
    ("row1 title", (60, 128, 300, 149), bright),
    ("row1 meta", (60, 149, 300, 168), grey),
    ("row1 bubble", (60, 168, 77, 186), amber),
    ("row1 line", (78, 168, 340, 186), amber),
    ("W header title", (35, 284, 92, 304), grey),
    ("W trailing", (300, 284, 386, 304), grey),
    ("W row1 time", (14, 316, 50, 338), green),
    ("W row1 dot", (59, 358, 73, 372), green),
    ("W row1 line", (73, 356, 130, 374), grey),
    ("R row3 title (dim)", (60, 729, 260, 751), lambda p: sum(p) / 3 > 90),
]
print(f"{'element':20} {'board x0,y0-x1,y1':>22}  {'app':>22}   dx/dy")
for name, box, pred in regions:
    b, a = ink(board, box, pred), ink(app, box, pred)
    d = "" if not (a and b) else f"{a[0]-b[0]:+d},{a[1]-b[1]:+d}  w{(a[2]-a[0])-(b[2]-b[0]):+d} h{(a[3]-a[1])-(b[3]-b[1]):+d}"
    print(f"{name:20} {str(b):>22}  {str(a):>22}   {d}")
