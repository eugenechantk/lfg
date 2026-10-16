# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Batch pixel measurements on 3x images. Coordinates in pt (px/3).
Query file lines:  label | image | op | x y w h | extra
ops:
  bbox  thr      -> ink bbox (pixels differing from region mode by > thr, max channel)
  rows  thr      -> runs of rows containing ink (pt), merged gaps < 1px
  cols  thr      -> runs of columns containing ink
  color          -> median RGB of region
  mode           -> most common RGB of region
Images: names resolved relative to EVID dir (first arg).
"""
import sys
import numpy as np
from PIL import Image
from collections import Counter

base = sys.argv[1]
qfile = sys.argv[2]
cache = {}

def img(name):
    if name not in cache:
        cache[name] = np.asarray(Image.open(f'{base}/{name}').convert('RGB')).astype(np.int16)
    return cache[name]

def region(a, x, y, w, h):
    X0, Y0 = int(round(x * 3)), int(round(y * 3))
    X1, Y1 = int(round((x + w) * 3)), int(round((y + h) * 3))
    return a[Y0:Y1, X0:X1], X0, Y0

def mode(r):
    flat = r.reshape(-1, 3)
    c = Counter(map(tuple, flat[:: max(1, len(flat) // 20000)]))
    return np.array(c.most_common(1)[0][0], dtype=np.int16)

def runs(mask):
    out = []
    i = 0
    n = len(mask)
    while i < n:
        if mask[i]:
            j = i
            while j + 1 < n and mask[j + 1]:
                j += 1
            out.append((i, j))
            i = j + 1
        else:
            i += 1
    return out

for line in open(qfile):
    line = line.strip()
    if not line or line.startswith('#'):
        continue
    parts = [p.strip() for p in line.split('|')]
    label, name, op, geo = parts[:4]
    extra = parts[4] if len(parts) > 4 else ''
    x, y, w, h = map(float, geo.split())
    a = img(name)
    r, X0, Y0 = region(a, x, y, w, h)
    if op in ('bbox', 'rows', 'cols', 'ink'):
        ex = extra.split()
        thr = float(ex[0]) if ex else 40
        bg = np.array([int(v) for v in ex[1].split(',')], dtype=np.int16) if len(ex) > 1 else mode(r)
        ink = (np.abs(r - bg).max(axis=2) > thr)
        if not ink.any():
            print(f'{label}: no ink (bg {tuple(bg)})'); continue
        ys, xs = np.where(ink)
        if op == 'ink':
            d = np.abs(r - bg).max(axis=2)
            sel = d >= 0.9 * d.max()
            med = np.median(r[sel].reshape(-1, 3), axis=0)
            print(f'{label}: ink {tuple(int(v) for v in med)} #{"".join(f"{int(v):02X}" for v in med)} (n={int(sel.sum())}, bg {tuple(int(v) for v in bg)})')
            continue
        if op == 'bbox':
            print(f'{label}: bbox x {(X0 + xs.min()) / 3:.2f}..{(X0 + xs.max() + 1) / 3:.2f}  y {(Y0 + ys.min()) / 3:.2f}..{(Y0 + ys.max() + 1) / 3:.2f}  (w {(xs.max() - xs.min() + 1) / 3:.2f} h {(ys.max() - ys.min() + 1) / 3:.2f}) bg {tuple(int(v) for v in bg)}')
        elif op == 'rows':
            rr = runs(ink.any(axis=1))
            print(f'{label}: rows ' + ', '.join(f'{(Y0 + s) / 3:.2f}..{(Y0 + e + 1) / 3:.2f}' for s, e in rr) + f'  bg {tuple(int(v) for v in bg)}')
        else:
            cc = runs(ink.any(axis=0))
            print(f'{label}: cols ' + ', '.join(f'{(X0 + s) / 3:.2f}..{(X0 + e + 1) / 3:.2f}' for s, e in cc) + f'  bg {tuple(int(v) for v in bg)}')
    elif op == 'color':
        med = np.median(r.reshape(-1, 3), axis=0)
        print(f'{label}: median {tuple(int(v) for v in med)} #{"".join(f"{int(v):02X}" for v in med)}')
    elif op == 'pct':
        flat = r.reshape(-1, 3)
        lum = flat.mean(axis=1)
        idx = np.argsort(lum)
        top = flat[idx[-max(1, len(idx)//200):]]
        print(f'{label}: max {tuple(int(v) for v in flat.max(axis=0))} top0.5% median {tuple(int(v) for v in np.median(top, axis=0))}')
    elif op == 'mode':
        m = mode(r)
        print(f'{label}: mode {tuple(int(v) for v in m)} #{"".join(f"{int(v):02X}" for v in m)}')
