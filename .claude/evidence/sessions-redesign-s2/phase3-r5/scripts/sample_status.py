"""Sample the tmux status-line fill (ANSI green bg) and its text colour in the app frames."""
from px import *

for f in ("app/term-fit-kbup.png", "app/term-wide-kbhidden.png"):
    a = load(f)
    g = (a[:, :, 1] > 150) & (a[:, :, 0] < 90) & (a[:, :, 2] < 90)
    b = bbox_mask(g[:2470])
    print(f, "status fill", hexc(color_at(a, b[2] - 6, (b[1] + b[3]) // 2, 2)), "bbox pt", pt(b))
