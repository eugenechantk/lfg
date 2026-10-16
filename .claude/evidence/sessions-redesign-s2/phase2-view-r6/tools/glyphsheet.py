# /// script
# dependencies = ["pillow"]
# ///
"""glyphsheet.py out.png board3x.png app.png name:x0,y0,x1,y1 ... (app rects in pt, scale 3)
Board glyph strip (board SVGs re-rendered at 3x in Chrome) on top, app native 3x crops below, each labelled.
Mechanical only: it never grades."""
import sys
from PIL import Image, ImageDraw

out, gpath, apath = sys.argv[1:4]
g = Image.open(gpath).convert("RGB")
a = Image.open(apath).convert("RGB")
crops = []
for spec in sys.argv[4:]:
    n, r = spec.split(":")
    x0, y0, x1, y1 = [float(v) for v in r.split(",")]
    crops.append((n, a.crop((int(x0 * 3), int(y0 * 3), int(x1 * 3), int(y1 * 3)))))
W = max(g.width, sum(c.width + 10 for _, c in crops))
H = g.height + 20 + max(c.height for _, c in crops) + 14
s = Image.new("RGB", (W, H), (60, 0, 60))
s.paste(g, (0, 0))
d = ImageDraw.Draw(s)
x = 0
for n, c in crops:
    s.paste(c, (x, g.height + 20))
    d.text((x, g.height + 22 + c.height), n, fill=(255, 255, 0))
    x += c.width + 10
d.text((2, g.height + 4), "board SVG at 3x (top) / app native 3x crops (bottom)", fill=(255, 255, 0))
s = s.resize((s.width * 2, s.height * 2), Image.NEAREST)
s.save(out)
print(out, s.size)
