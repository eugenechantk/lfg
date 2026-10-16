# /// script
# dependencies = ["pillow"]
# ///
"""Stitch 585x1266 tiles into 1170x2532 board renders (3x).
Tile files: board/<prefix>-t00/t10/t01/t11.png (t<col><row>).
A tile can come from another prefix via an override map."""
import os, hashlib
from PIL import Image

B = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "board")
POS = {"t00": (0, 0), "t10": (585, 0), "t01": (0, 1266), "t11": (585, 1266)}
SETS = {
    "kbc-fit": {},
    "kbc-fit-keysend": {"t00": "kbc-fit", "t10": "kbc-fit"},
    "kbc-wide": {},
    "kbo-wide": {},
    "kbo-fit": {},
    "signin": {},
}
for name, over in SETS.items():
    canvas = Image.new("RGB", (1170, 2532))
    for t, (x, y) in POS.items():
        src = over.get(t, name)
        im = Image.open(os.path.join(B, f"{src}-{t}.png")).convert("RGB")
        assert im.size == (585, 1266), (src, t, im.size)
        canvas.paste(im, (x, y))
    out = os.path.join(B, f"board-{name}-3x.png")
    canvas.save(out)
    print(out, hashlib.sha256(open(out, "rb").read()).hexdigest()[:12])
