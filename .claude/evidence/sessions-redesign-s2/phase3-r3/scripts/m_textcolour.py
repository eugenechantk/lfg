# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Terminal default-foreground colour: percentiles of glyph pixels (board '0 fail' / app 'sh-3.2$'),
plus a white reference (the 'Terminal' title, #F2F2F7 on the board) from the same frames."""
import glob, os
from lib import *

def pct(reg, q):
    g = reg.max(axis=2).reshape(-1)
    g = g[g > 60]
    return np.percentile(g, q)

B = load("board/board-terminal-kb-3x.png")
print("board '0 fail' p90/p98/max", pct(B[1385:1410, 150:300], 90), pct(B[1385:1410, 150:300], 98), B[1385:1410, 150:300].max())
print("board title p98/max", pct(B[195:240, 410:615], 98), B[195:240, 410:615].max())
p90, p98, t98 = [], [], []
for f in sorted(glob.glob(os.path.join(E, "app", "cursorframes", "*.png"))):
    a = load(os.path.relpath(f, E))
    r = a[375:412, 36:205]
    p90.append(pct(r, 90)); p98.append(pct(r, 98))
    t98.append(pct(a[219:265, 435:630], 98))
print("app prompt p90 mean %.1f  p98 mean %.1f (n=%d)" % (np.mean(p90), np.mean(p98), len(p90)))
print("app title p98 mean %.1f" % np.mean(t98))
