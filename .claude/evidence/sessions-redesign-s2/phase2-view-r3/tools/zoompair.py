# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""zoompair.py out.png design.png dscale dx0,dy0,dx1,dy1 app.png ascale ax0,ay0,ax1,ay1 [zoom]
Crops both (rects in points), scales both to the same points->pixels (zoom px per pt, nearest), stacks side by side."""
import sys
from PIL import Image

out = sys.argv[1]
zoom = float(sys.argv[8]) if len(sys.argv) > 8 else 4

def crop(path, scale, rect):
    x0, y0, x1, y1 = [float(v) for v in rect.split(",")]
    im = Image.open(path).convert("RGB").crop((int(x0 * scale), int(y0 * scale), int(x1 * scale), int(y1 * scale)))
    return im.resize((int((x1 - x0) * zoom), int((y1 - y0) * zoom)), Image.NEAREST)

a = crop(sys.argv[2], float(sys.argv[3]), sys.argv[4])
b = crop(sys.argv[5], float(sys.argv[6]), sys.argv[7])
W = a.width + b.width + 20
H = max(a.height, b.height)
sheet = Image.new("RGB", (W, H), (255, 0, 255))
sheet.paste(a, (0, 0))
sheet.paste(b, (a.width + 20, 0))
sheet.save(out)
print(out, sheet.size)
