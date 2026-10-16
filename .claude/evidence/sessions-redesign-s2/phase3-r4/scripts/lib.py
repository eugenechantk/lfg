"""Shared pixel helpers (imported by the per-board measure scripts)."""
import numpy as np
from PIL import Image
import os

E = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def load(rel):
    return np.asarray(Image.open(os.path.join(E, rel)).convert("RGB")).astype(int)


def runs_of(v):
    out, start = [], None
    for i, b in enumerate(v):
        if b and start is None:
            start = i
        if not b and start is not None:
            out.append((start, i - 1)); start = None
    if start is not None:
        out.append((start, len(v) - 1))
    return out


def modal(reg):
    flat = reg.reshape(-1, 3)
    vals, counts = np.unique(flat, axis=0, return_counts=True)
    return vals[counts.argmax()]


def ink(a, x0, y0, x1, y1, thr=30, bg=None):
    """Return (mask, bg) of pixels differing from bg (modal if None) by > thr in the px box."""
    reg = a[y0:y1, x0:x1]
    b = modal(reg) if bg is None else np.array(bg)
    return np.abs(reg - b).max(axis=2) > thr, b


def bbox(a, x0, y0, x1, y1, thr=30, bg=None):
    m, b = ink(a, x0, y0, x1, y1, thr, bg)
    ys, xs = np.where(m)
    if len(xs) == 0:
        return None
    return (xs.min() + x0, ys.min() + y0, xs.max() + x0 + 1, ys.max() + y0 + 1)


def rows(a, x0, y0, x1, y1, thr=30, bg=None):
    """Ink runs along y; each with its x extent. px, end-exclusive."""
    m, b = ink(a, x0, y0, x1, y1, thr, bg)
    out = []
    for s, e in runs_of(m.any(axis=1)):
        xs = np.where(m[s:e + 1].any(axis=0))[0]
        out.append((s + y0, e + y0 + 1, xs.min() + x0, xs.max() + x0 + 1))
    return out


def cols(a, x0, y0, x1, y1, thr=30, bg=None):
    m, b = ink(a, x0, y0, x1, y1, thr, bg)
    out = []
    for s, e in runs_of(m.any(axis=0)):
        ys = np.where(m[:, s:e + 1].any(axis=1))[0]
        out.append((s + x0, e + x0 + 1, ys.min() + y0, ys.max() + y0 + 1))
    return out


def vedges(a, x, y0=0, y1=None, thr=6):
    col = a[y0:y1, x]
    out = []
    for i in range(1, len(col)):
        if np.abs(col[i] - col[i - 1]).max() > thr:
            out.append((i + y0, col[i - 1].tolist(), col[i].tolist()))
    return out


def hedges(a, y, x0=0, x1=None, thr=6):
    row = a[y, x0:x1]
    out = []
    for i in range(1, len(row)):
        if np.abs(row[i] - row[i - 1]).max() > thr:
            out.append((i + x0, row[i - 1].tolist(), row[i].tolist()))
    return out


def pt(v, scale=3.0, off=0.0, s=1.0):
    """px -> pt, minus an offset (pt), divided by the sheet scale s."""
    return round((v / scale - off) / s, 2)
