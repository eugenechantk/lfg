"""Pixel helpers shared by the round-5 measure scripts. All images are 3x."""
import os
import numpy as np
from PIL import Image

E = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def load(rel):
    return np.asarray(Image.open(os.path.join(E, rel)).convert("RGB")).astype(int)


def runs(v):
    out, s = [], None
    for i, b in enumerate(v):
        if b and s is None:
            s = i
        if not b and s is not None:
            out.append((s, i)); s = None
    if s is not None:
        out.append((s, len(v)))
    return out  # end-exclusive


def mask_diff(a, x0, y0, x1, y1, ref, thr):
    reg = a[y0:y1, x0:x1]
    return np.abs(reg - np.array(ref)).max(axis=2) > thr


def bbox_mask(m, x0=0, y0=0):
    ys, xs = np.where(m)
    if len(xs) == 0:
        return None
    return (int(xs.min() + x0), int(ys.min() + y0), int(xs.max() + x0 + 1), int(ys.max() + y0 + 1))


def bbox_diff(a, x0, y0, x1, y1, ref, thr):
    return bbox_mask(mask_diff(a, x0, y0, x1, y1, ref, thr), x0, y0)


def bbox_bright(a, x0, y0, x1, y1, thr):
    reg = a[y0:y1, x0:x1]
    return bbox_mask(reg.min(axis=2) > thr, x0, y0)


def bbox_lum(a, x0, y0, x1, y1, lo, hi=999):
    reg = a[y0:y1, x0:x1].mean(axis=2)
    return bbox_mask((reg > lo) & (reg < hi), x0, y0)


def pt(b, ox=0, oy=0):
    """px bbox -> pt (x, y, w, h) with an optional pt origin offset."""
    if b is None:
        return None
    x0, y0, x1, y1 = b
    return (round(x0 / 3 - ox, 2), round(y0 / 3 - oy, 2), round((x1 - x0) / 3, 2), round((y1 - y0) / 3, 2))


def color_at(a, x, y, r=2):
    reg = a[y - r:y + r + 1, x - r:x + r + 1].reshape(-1, 3)
    return tuple(int(v) for v in np.median(reg, axis=0))


def hexc(c):
    return "#%02X%02X%02X" % tuple(c)


def corner_radius_px(a, x_left, y_top, ref_bg, thr, depth=60):
    """Rows from the shape's top edge until its left edge reaches x_left (px)."""
    for k in range(depth):
        row = a[y_top + k, x_left:x_left + depth]
        m = np.abs(row - np.array(ref_bg)).max(axis=1) > thr
        if m.size and m[0]:
            return k
    return None
