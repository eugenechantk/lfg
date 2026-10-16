"""zoom.py <root> <state> <x> <y> <w> <h> <scale> <outname>: board crop above app crop, nearest-neighbour upscaled, same rect in both."""
import os
import sys

from PIL import Image, ImageDraw

root, st = sys.argv[1], sys.argv[2]
x, y, w, h, k = map(int, sys.argv[3:8])
out = sys.argv[8]
os.chdir(root)
b = Image.open(f"board-{st}.png").convert("RGB").crop((x, y, x + w, y + h)).resize((w * k, h * k), Image.NEAREST)
a = Image.open(f"app-{st}-srgb.png").convert("RGB").crop((x, y, x + w, y + h)).resize((w * k, h * k), Image.NEAREST)
im = Image.new("RGB", (w * k, 2 * h * k + 30), (90, 0, 90))
im.paste(b, (0, 12))
im.paste(a, (0, h * k + 30))
d = ImageDraw.Draw(im)
d.text((2, 0), f"board {st} [{x},{y},{w},{h}] x{k}", fill=(255, 255, 255))
d.text((2, h * k + 16), "app (sRGB)", fill=(255, 255, 255))
os.makedirs("zoom", exist_ok=True)
im.save(os.path.join("zoom", out))
print(os.path.join(root, "zoom", out), im.size)
