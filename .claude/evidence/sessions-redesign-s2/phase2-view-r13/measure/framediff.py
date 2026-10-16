# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Diff this round's app frames against an earlier round's frames of the same state.
Reports row bands (pt) whose max channel difference exceeds a threshold, ignoring the
status bar (y < 60pt) and the header timer region. Used only to locate change, not to judge.
usage: framediff.py OLD_DIR NEW_DIR name [name...]
"""
import sys
import numpy as np
from PIL import Image

old, new = sys.argv[1], sys.argv[2]
import os
THR = int(os.environ.get("THR", "40"))
for name in sys.argv[3:]:
    a = np.asarray(Image.open(f'{old}/{name}.png').convert('RGB')).astype(np.int16)
    b = np.asarray(Image.open(f'{new}/{name}.png').convert('RGB')).astype(np.int16)
    d = np.abs(a - b).max(axis=2)
    d[:180, :] = 0            # status bar
    d[600:720, 600:1100] = 0  # header status-line timer (y 200-240pt, x 200-367pt)
    rows = (d > THR).sum(axis=1) > 3
    bands = []
    i = 0
    while i < len(rows):
        if rows[i]:
            j = i
            while j + 1 < len(rows) and (rows[j + 1] or (j + 4 < len(rows) and rows[j + 4])):
                j += 1
            cols = np.where((d[i:j + 1] > THR).any(axis=0))[0]
            bands.append(f'{i/3:.1f}-{j/3:.1f}pt x{cols.min()/3:.0f}-{cols.max()/3:.0f}')
            i = j + 1
        else:
            i += 1
    print(name, 'identical' if not bands else '; '.join(bands))
