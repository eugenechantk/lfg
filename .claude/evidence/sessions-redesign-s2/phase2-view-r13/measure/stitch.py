# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Stitch 5 board tiles into a 1170x2532 3x render and verify overlaps.
usage: stitch.py OUT.png t1 t2 t3 s1 s2
 t1,t2,t3: 1135x1000 tiles at artboard y=0,1000,1532 (x=0)
 s1,s2: 70x1266 strips at artboard x=1100, y=0 and y=1266
"""
import sys
import numpy as np
from PIL import Image

out, t1, t2, t3, s1, s2 = sys.argv[1:7]
W, H = 1170, 2532
canvas = np.zeros((H, W, 3), dtype=np.int16)
filled = np.zeros((H, W), dtype=bool)
report = []

def place(path, x, y, exp):
    im = np.asarray(Image.open(path).convert('RGB')).astype(np.int16)
    h, w = im.shape[:2]
    assert (w, h) == exp, f'{path} is {w}x{h}, expected {exp}'
    region = canvas[y:y+h, x:x+w]
    f = filled[y:y+h, x:x+w]
    if f.any():
        d = np.abs(region[f] - im[f]).max()
        report.append(f'{path.split("/")[-1]} overlap {int(f.sum())} px, max channel diff {int(d)}')
    canvas[y:y+h, x:x+w] = im
    filled[y:y+h, x:x+w] = True

place(t1, 0, 0, (1135, 1000))
place(t2, 0, 1000, (1135, 1000))
place(t3, 0, 1532, (1135, 1000))
place(s1, 1100, 0, (70, 1266))
place(s2, 1100, 1266, (70, 1266))
assert filled.all(), f'unfilled px: {int((~filled).sum())}'
Image.fromarray(canvas.astype(np.uint8)).save(out)
print(out, 'ok'); print('\n'.join(report))
