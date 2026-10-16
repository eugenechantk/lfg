# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""samp.py <img>@<scale> x,y x,y ... [<img2>@<scale> x,y ...] -> mean colour of the 1pt cell at each point (logical points)."""
import sys
import numpy as np
from PIL import Image

img = None
for a in sys.argv[1:]:
    if "@" in a:
        p, s = a.split("@")
        img = np.asarray(Image.open(p).convert("RGB")).astype(float)
        sc = float(s)
        print(p.split("/")[-1], end=": ")
        continue
    x, y = [float(v) for v in a.split(",")]
    X, Y, n = int(x * sc), int(y * sc), max(1, int(sc))
    c = img[Y:Y + n, X:X + n].reshape(-1, 3).mean(axis=0)
    print(f"({x:g},{y:g})#{int(round(c[0])):02X}{int(round(c[1])):02X}{int(round(c[2])):02X}", end="  ")
    if a == sys.argv[-1] or "@" in sys.argv[sys.argv.index(a) + 1]:
        print()
