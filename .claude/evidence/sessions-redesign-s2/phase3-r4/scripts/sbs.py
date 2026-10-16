# /// script
# dependencies = ["pillow"]
# ///
"""Side-by-side of native crops (design left, app right), each upscaled k× with nearest neighbour.
usage: sbs.py <out.png> <k> <design.png> <app.png> [<design2> <app2> ...]  (rows of pairs)"""
import sys
from PIL import Image

out, k = sys.argv[1], int(sys.argv[2])
files = sys.argv[3:]
rows = []
for i in range(0, len(files), 2):
    d, a = Image.open(files[i]).convert("RGB"), Image.open(files[i + 1]).convert("RGB")
    d = d.resize((d.width * k, d.height * k), Image.NEAREST)
    a = a.resize((a.width * k, a.height * k), Image.NEAREST)
    row = Image.new("RGB", (d.width + a.width + 12, max(d.height, a.height)), (255, 0, 255))
    row.paste(d, (0, 0)); row.paste(a, (d.width + 12, 0))
    rows.append(row)
W = max(r.width for r in rows)
H = sum(r.height for r in rows) + 12 * (len(rows) - 1)
canvas = Image.new("RGB", (W, H), (255, 0, 255))
y = 0
for r in rows:
    canvas.paste(r, (0, y)); y += r.height + 12
canvas.save(out)
print(out, canvas.size)
