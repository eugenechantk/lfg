# /// script
# dependencies = ["pillow"]
# ///
"""zoom.py <crops-dir> <out-dir> <scale> <id> [id ...]: stack design (top) over app (bottom), nearest-neighbour scaled.
Viewing aid only; measurements come from the native crops."""
import os, sys
from PIL import Image, ImageDraw

src, out, scale = sys.argv[1], sys.argv[2], int(sys.argv[3])
os.makedirs(out, exist_ok=True)
for cid in sys.argv[4:]:
    d = Image.open(os.path.join(src, f"{cid}-design.png")).convert("RGB")
    a = Image.open(os.path.join(src, f"{cid}-app.png")).convert("RGB")
    w, h = max(d.width, a.width), d.height + a.height + 4
    canvas = Image.new("RGB", (w, h), (255, 0, 255))
    canvas.paste(d, (0, 0)); canvas.paste(a, (0, d.height + 4))
    canvas = canvas.resize((w * scale, h * scale), Image.NEAREST)
    canvas.save(os.path.join(out, f"{cid}-zoom{scale}x.png"))
    print(cid)
