# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""shadowprof.py: sample the strip under/beside the open menu on a board (1x) and the app frame (3x).
Board strip top = 682, app strip top = 713 (+31). Horizontal: right-anchored, app_x = board_x + 11.
Prints the mean colour of the 1pt cell; a 2pt grid across the strip rows (dy from strip top) and columns."""
import sys
import numpy as np
from PIL import Image

def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(float)

def cell(a, s, x, y):
    X, Y, n = int(x * s), int(y * s), max(1, int(s))
    c = a[Y:Y + n, X:X + n].reshape(-1, 3).mean(axis=0)
    return "#%02X%02X%02X" % tuple(int(round(v)) for v in c)

board, app = sys.argv[1], sys.argv[2]
b, a = load(board), load(app)
bxs = [int(v) for v in (sys.argv[3] if len(sys.argv) > 3 else "30,60,100,120,128,140,160,200,250,300,340").split(",")]
dys = [1, 2, 3, 5, 7, 25, 27, 29, 30]
print("dy\\bx  " + " ".join(f"{x:>17d}" for x in bxs))
for dy in dys:
    row = []
    for x in bxs:
        row.append(f"{cell(b, 1, x, 682 + dy)}/{cell(a, 3, x + 11, 713 + dy)}")
    print(f"{dy:5d}  " + " ".join(f"{r:>17s}" for r in row))
print("cells are board/app (board 1x, app 3x h264)")
