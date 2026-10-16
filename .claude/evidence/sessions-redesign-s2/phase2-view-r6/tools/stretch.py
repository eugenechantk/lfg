# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""stretch.py out.png lo hi  board.png bscale bx0,by0,bx1,by1  app.png ascale ax0,ay0,ax1,ay1  [zoom]
Contrast-stretches luminance lo..hi -> 0..255 on both crops (rects in pt), scales both to zoom px/pt, stacks
board above app. For seeing faint show-through and shadow footprints. Mechanical only."""
import sys
import numpy as np
from PIL import Image

out, lo, hi = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
zoom = float(sys.argv[10]) if len(sys.argv) > 10 else 3

def crop(path, s, rect):
    x0, y0, x1, y1 = [float(v) for v in rect.split(",")]
    im = Image.open(path).convert("L").crop((int(x0 * s), int(y0 * s), int(x1 * s), int(y1 * s)))
    a = np.asarray(im).astype(float)
    a = np.clip((a - lo) / (hi - lo) * 255, 0, 255).astype(np.uint8)
    im = Image.fromarray(a)
    return im.resize((int((x1 - x0) * zoom), int((y1 - y0) * zoom)), Image.NEAREST)

b = crop(sys.argv[4], float(sys.argv[5]), sys.argv[6])
a = crop(sys.argv[7], float(sys.argv[8]), sys.argv[9])
W = max(a.width, b.width)
sheet = Image.new("L", (W, a.height + b.height + 10), 128)
sheet.paste(b, (0, 0))
sheet.paste(a, (0, b.height + 10))
sheet.save(out)
print(out, sheet.size)
