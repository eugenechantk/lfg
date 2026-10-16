"""Put a design board screenshot next to an app screenshot at the same height, with labels.
usage: side_by_side.py <design.jpg> <app.jpg> <out.png> [crop_w crop_h of the design area]"""
import sys
from PIL import Image, ImageDraw
design, app, out = sys.argv[1:4]
d = Image.open(design).convert("RGB")
if len(sys.argv) > 5:
    d = d.crop((0, 0, int(sys.argv[4]), int(sys.argv[5])))
a = Image.open(app).convert("RGB")
H = 900
d = d.resize((round(d.width * H / d.height), H)); a = a.resize((round(a.width * H / a.height), H))
pad, top = 24, 40
img = Image.new("RGB", (d.width + a.width + pad * 3, H + top + pad), (24, 24, 26))
img.paste(d, (pad, top)); img.paste(a, (d.width + pad * 2, top))
dr = ImageDraw.Draw(img)
dr.text((pad, 12), "Design board", fill=(230, 230, 230)); dr.text((d.width + pad * 2, 12), "App (iPhone 17 Pro sim)", fill=(230, 230, 230))
img.save(out); print(out, img.size)
