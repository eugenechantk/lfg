"""Title-band pixel diff (x>=80, outside the native window controls) and fill-colour samples, board vs app (sRGB)."""
import os
import sys

import numpy as np
from PIL import Image

os.chdir(sys.argv[1])


def lum(a):
    return 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def px(img, x, y):
    return "#%02X%02X%02X" % tuple(int(v) for v in img[y, x])


B = np.array(Image.open("board-open.png").convert("RGB")).astype(float)
A = np.array(Image.open("app-open-srgb.png").convert("RGB")).astype(float)
d = np.abs(lum(A[:52]) - lum(B[:52]))[2:50, 80:398]
ys, xs = np.where(d > 25)
print("title band x>=80: pixels with |dlum|>25:", len(ys))
if len(ys):
    print("  bbox x", xs.min() + 80, xs.max() + 80, " y", ys.min() + 2, ys.max() + 2)
samples = {
    "title-bar bg (100,5)": (100, 5),
    "track (228,26)": (228, 26),
    "track (298,26)": (298, 26),
    "selected pill (130,26)": (130, 26),
    "selected pill (215,26)": (215, 26),
    "Sessions badge (196,26)": (196, 26),
    "Tasks badge (274,26)": (274, 26),
    "Tasks badge app-shifted (275,26)": (275, 26),
    "search btn (362,26)": (362, 26),
    "search btn (373,14)": (373, 14),
    "body bg (200,120)": (200, 120),
    "body bg (30,300)": (30, 300),
    "body bg (200,840)": (200, 840),
    "By status pill (310,63)": (310, 63),
    "By status pill (380,63)": (380, 63),
    "list top border (200,82)": (200, 82),
    "row separator (200,195)": (200, 195),
    "row separator, faded row (200,797)": (200, 797),
    "Pro dot (19,63)": (19, 63),
    "Air ring board (62,63)": (62, 63),
    "Air ring app-shifted (63,63)": (63, 63),
    "working dot (65,364)": (65, 364),
    "working halo (60,364)": (60, 364),
    "working halo (65,359)": (65, 359),
}
for nm, (x, y) in samples.items():
    print(f"{nm:36s} board {px(B, x, y)}  app {px(A, x, y)}")
# separator start x on the first row separator (y=195): first column where the hairline is present
for nm, img in (("board", B), ("app", A)):
    row = lum(img[195])
    xs = np.where(row - 27 > 6)[0]
    print(f"row separator y=195 {nm}: x={xs.min()}..{xs.max()}")
    row = lum(img[82])
    xs = np.where(row - 27 > 6)[0]
    print(f"list top border y=82 {nm}: x={xs.min()}..{xs.max()}")
