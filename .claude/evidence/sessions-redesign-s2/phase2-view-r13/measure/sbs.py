# /// script
# dependencies = ["pillow"]
# ///
"""Native-resolution side-by-side: design | app for given pair ids. usage: sbs.py OUT id1 id2 ..."""
import sys
from PIL import Image, ImageDraw
D = '/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r12/crops'
out = sys.argv[1]
rows = []
for pid in sys.argv[2:]:
    a = Image.open(f'{D}/{pid}-design.png').convert('RGB')
    b = Image.open(f'{D}/{pid}-app.png').convert('RGB')
    w = a.width + b.width + 30
    h = max(a.height, b.height) + 40
    im = Image.new('RGB', (w, h), (90, 90, 90))
    im.paste(a, (0, 40)); im.paste(b, (a.width + 30, 40))
    d = ImageDraw.Draw(im)
    d.text((4, 4), f'{pid}  board (left) | app (right), native 3x px', fill=(255, 255, 255))
    rows.append(im)
W = max(r.width for r in rows); H = sum(r.height for r in rows)
sheet = Image.new('RGB', (W, H), (60, 60, 60))
y = 0
for r in rows:
    sheet.paste(r, (0, y)); y += r.height
sheet.save(out)
print(out, sheet.size)
