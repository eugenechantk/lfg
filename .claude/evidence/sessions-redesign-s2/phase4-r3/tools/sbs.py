"""Side-by-side (board | app | overlay) per state at 1x, top-aligned, no scaling. Overlay: board in red channel, app in green/blue."""
import os
import sys

from PIL import Image, ImageChops, ImageDraw

root = sys.argv[1]
os.chdir(root)
states = ["open", "fold-needs", "fold-working", "fold-recent", "fold-all"]
for s in states:
    b = Image.open(f"board-{s}.png").convert("RGB")
    a = Image.open(f"app-{s}-srgb.png").convert("RGB")
    H = max(b.height, a.height)
    W = b.width + a.width + max(b.width, a.width) + 20
    out = Image.new("RGB", (W, H + 16), (60, 60, 60))
    out.paste(b, (0, 16))
    out.paste(a, (b.width + 10, 16))
    bl = b.convert("L")
    al = a.convert("L").crop((0, 0, b.width, b.height))
    ov = Image.merge("RGB", (bl, al, al))
    out.paste(ov, (b.width + a.width + 20, 16))
    d = ImageDraw.Draw(out)
    d.text((4, 2), f"board {s}", fill=(255, 255, 255))
    d.text((b.width + 14, 2), f"app {s} (sRGB)", fill=(255, 255, 255))
    d.text((b.width + a.width + 24, 2), "overlay R=board GB=app", fill=(255, 255, 255))
    out.save(f"sbs-{s}.png")
    print("sbs", s, out.size)
