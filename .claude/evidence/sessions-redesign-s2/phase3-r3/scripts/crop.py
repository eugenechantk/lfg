# /// script
# dependencies = ["pillow"]
# ///
"""Crop a pixel box and optionally upscale (nearest) for viewing.
usage: crop.py <src> <out> x0 y0 x1 y1 [scale]"""
import sys
from PIL import Image

src, out = sys.argv[1], sys.argv[2]
x0, y0, x1, y1 = map(int, sys.argv[3:7])
s = float(sys.argv[7]) if len(sys.argv) > 7 else 1
im = Image.open(src).convert("RGB").crop((x0, y0, x1, y1))
if s != 1:
    im = im.resize((int(im.width * s), int(im.height * s)), Image.NEAREST)
im.save(out)
print(out, im.size)
