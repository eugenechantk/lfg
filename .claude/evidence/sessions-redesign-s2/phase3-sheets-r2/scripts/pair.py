# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Quick review pair: board crop | app crop (app normalised by 1/s), both in sheet pt, enlarged.
usage: pair.py <out.png> <zoom> <board_img> <board_sheet_top> <app_frame> bx by bw bh ax ay aw ah
(rects in sheet-relative laid-out pt)."""
import sys, os, json
from PIL import Image

E = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
out, zoom, bimg, btop, af = sys.argv[1], float(sys.argv[2]), sys.argv[3], float(sys.argv[4]), sys.argv[5]
bx, by, bw, bh, ax, ay, aw, ah = map(float, sys.argv[6:14])
b = Image.open(os.path.join(E, "board", bimg)).convert("RGB")
bc = b.crop((round(bx * 3), round((by + btop) * 3), round((bx + bw) * 3), round((by + btop + bh) * 3)))
g = json.load(open(os.path.join(E, "scripts", "geom.json")))[af]
a = Image.open(os.path.join(E, "app", f"{af}.png")).convert("RGB")
L, T, s = g["L"], g["T"], g["s"]
ac = a.crop((round(L + ax * 3 * s), round(T + ay * 3 * s), round(L + (ax + aw) * 3 * s), round(T + (ay + ah) * 3 * s)))
ac = ac.resize((round(aw * 3), round(ah * 3)), Image.LANCZOS)
z = lambda im: im.resize((round(im.width * zoom / 3), round(im.height * zoom / 3)), Image.NEAREST)
bc, ac = z(bc), z(ac)
W = bc.width + ac.width + 12
canvas = Image.new("RGB", (W, max(bc.height, ac.height)), (255, 0, 255))
canvas.paste(bc, (0, 0)); canvas.paste(ac, (bc.width + 12, 0))
canvas.save(os.path.join(E, "crops", out))
print(out, canvas.size)
