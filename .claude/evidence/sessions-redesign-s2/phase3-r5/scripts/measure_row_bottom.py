"""Key row bottom edge in the keyboard-hidden state (column scan at x = 4pt and x = 201pt)."""
from px import *

for tag, f, H, y0 in [("board kbc", "board/board-kbc-fit-3x.png", 844, 750), ("app kbhidden", "app/term-fit-kbhidden-keystart.png", 874, 780)]:
    a = load(f)
    for xpt in (4, 201):
        col = [hexc(a[y, xpt * 3]) for y in range(y0 * 3, H * 3, 3)]
        print(tag, "x", xpt, "pt rows from", y0, ":", " ".join(col))
