# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Print vertical colour transitions in an app/board image column (px). usage: vcheck.py <rel img> x y0 y1 [thr]"""
import sys
from lib import load, vedges

a = load(sys.argv[1])
x, y0, y1 = int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
thr = int(sys.argv[5]) if len(sys.argv) > 5 else 3
print("start", a[y0, x].tolist())
for e in vedges(a, x, y0, y1, thr):
    print(e[0], round(e[0] / 3, 2), e[1], "->", e[2])
