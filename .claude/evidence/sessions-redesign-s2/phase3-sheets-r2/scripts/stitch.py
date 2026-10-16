# /// script
# dependencies = ["pillow"]
# ///
"""Stitch four 585x1266 tiles (t00,t10,t01,t11) into a 1170x2532 board render.
usage: stitch.py <board_dir> <prefix> <out.png>"""
import sys, os
from PIL import Image

d, prefix, out = sys.argv[1:4]
canvas = Image.new("RGB", (1170, 2532))
for name, (x, y) in {"t00": (0, 0), "t10": (585, 0), "t01": (0, 1266), "t11": (585, 1266)}.items():
    im = Image.open(os.path.join(d, f"{prefix}-{name}.png")).convert("RGB")
    assert im.size == (585, 1266), im.size
    canvas.paste(im, (x, y))
canvas.save(out)
print(out, canvas.size)
