# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Board vs app measurement helpers (both images 1 px = 1 pt, top-aligned, title bar included).

Commands:
  elements <board.png> <app-srgb.png> <board-dom.tsv> <out.tsv>
      For each text node / dot / svg / filled box in the DOM dump: ink bbox and core colour in both images
      inside the DOM box (+4 px x, +2 px y). Ink = pixels > 22 levels (max channel) from the region's border median.
  seps <img.png> <x> [y0 y1]   rows in column x that differ from the rows around them (separators / edges)
  row <img.png> <y> <x0> <x1>  print pixels of a row
  col <img.png> <x> <y0> <y1>  print pixels of a column
  xruns <img.png> <x0> <y0> <x1> <y1> [thr]  ink column runs inside a box
  yruns <img.png> <x0> <y0> <x1> <y1> [thr]  ink row runs inside a box
  diff <board.png> <app.png> <out.png> <h>   abs diff of the top h rows (amplified x4)
  px <img.png> x y [x y ...]
"""
import sys, re
import numpy as np
from PIL import Image


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(int)


def border_bg(a, x0, y0, x1, y1):
    reg = a[y0:y1, x0:x1]
    edge = np.concatenate([reg[0], reg[-1], reg[:, 0], reg[:, -1]])
    return np.median(edge, axis=0)


def ink(a, x0, y0, x1, y1, thr=22):
    h, w = a.shape[:2]
    x0, y0, x1, y1 = max(0, x0), max(0, y0), min(w, x1), min(h, y1)
    reg = a[y0:y1, x0:x1]
    bg = border_bg(a, x0, y0, x1, y1)
    d = np.abs(reg - bg).max(axis=2)
    m = d > thr
    if not m.any():
        return None
    ys, xs = np.where(m)
    bx0, by0, bx1, by1 = xs.min() + x0, ys.min() + y0, xs.max() + x0, ys.max() + y0
    # core colour: mean of the 15% of ink pixels farthest from bg
    dv = d[m]
    cut = np.quantile(dv, 0.85)
    core = reg[m][dv >= cut].mean(axis=0)
    touches = bx0 == x0 or by0 == y0 or bx1 == x1 - 1 or by1 == y1 - 1
    return (bx0, by0, bx1, by1), tuple(int(round(c)) for c in core), tuple(int(round(c)) for c in bg), touches


def parse_dom(p):
    els = []
    for line in open(p):
        f = line.rstrip("\n").split("\t")
        idx, tag = f[0], f[1]
        x, y, w, h = map(float, f[2:6])
        kv = {}
        for item in f[6:]:
            k, _, v = item.partition("=")
            kv[k] = v
        els.append(dict(idx=int(idx), tag=tag, x=x, y=y, w=w, h=h, **kv))
    return els


def elements(board, app, dom, out):
    A, B = load(app), load(board)
    rows = []
    for e in parse_dom(dom):
        items = []
        if e["txt"]:
            for t in e["txt"].split(" | "):
                label, _, box = t.rpartition("@")
                x, y, w, h = map(float, box.split(","))
                items.append((f"text:{label}", x, y, w, h))
        elif e["tag"] in ("svg",):
            items.append((f"svg#{e['idx']}", e["x"], e["y"], e["w"], e["h"]))
        elif e["tag"] == "span" and e["w"] <= 16 and e["h"] <= 16 and e["bg"] != "rgba(0, 0, 0, 0)" and not e["txt"]:
            items.append((f"dot#{e['idx']} {e['bg']}", e["x"], e["y"], e["w"], e["h"]))
        elif e["tag"] == "span" and e["w"] <= 8 and e["h"] <= 8 and "1.5px" in e.get("bd", ""):
            items.append((f"ring#{e['idx']}", e["x"], e["y"], e["w"], e["h"]))
        for name, x, y, w, h in items:
            x0, y0 = int(np.floor(x)) - 4, int(np.floor(y)) - 2
            x1, y1 = int(np.ceil(x + w)) + 4, int(np.ceil(y + h)) + 2
            rb, ra = ink(B, x0, y0, x1, y1), ink(A, x0, y0, x1, y1)
            def fmt(r):
                if not r:
                    return "none", "", ""
                (a0, b0, a1, b1), core, bg, t = r
                return f"{a0},{b0},{a1},{b1}" + (" EDGE" if t else ""), f"{core}", f"{bg}"
            fb, fa = fmt(rb), fmt(ra)
            dl = dt = dr = db = ""
            if rb and ra:
                dl, dt, dr, db = [ra[0][i] - rb[0][i] for i in range(4)]
            rows.append([name, f"{x0},{y0},{x1},{y1}", fb[0], fa[0], dl, dt, dr, db, fb[1], fa[1], fb[2], fa[2]])
    with open(out, "w") as f:
        f.write("element\tregion\tboard_ink(x0,y0,x1,y1)\tapp_ink\tdL\tdT\tdR\tdB\tboard_core\tapp_core\tboard_bg\tapp_bg\n")
        for r in rows:
            f.write("\t".join(map(str, r)) + "\n")
    for r in rows:
        flag = ""
        if r[4] != "" and max(abs(r[4]), abs(r[5]), abs(r[6]), abs(r[7])) > 1:
            flag = "  <<"
        print("\t".join(map(str, r[:10])) + flag)


def seps(p, x, y0=0, y1=None):
    a = load(p)
    col = a[:, x]
    y1 = y1 or a.shape[0]
    prev = None
    for y in range(max(1, y0), min(y1, a.shape[0] - 1)):
        c = col[y]
        up, dn = col[y - 1], col[y + 1]
        if np.abs(c - up).max() > 4 and np.abs(c - dn).max() > 4:
            print(y, tuple(c), "above", tuple(up), "below", tuple(dn))


def xruns(p, x0, y0, x1, y1, thr=22):
    a = load(p)
    bg = border_bg(a, x0, y0, x1, y1)
    reg = a[y0:y1, x0:x1]
    m = (np.abs(reg - bg).max(axis=2) > thr).any(axis=0)
    runs, start = [], None
    for i, v in enumerate(m):
        if v and start is None:
            start = i
        if not v and start is not None:
            runs.append((start + x0, i - 1 + x0)); start = None
    if start is not None:
        runs.append((start + x0, len(m) - 1 + x0))
    print(runs)


def yruns(p, x0, y0, x1, y1, thr=22):
    a = load(p)
    bg = border_bg(a, x0, y0, x1, y1)
    reg = a[y0:y1, x0:x1]
    m = (np.abs(reg - bg).max(axis=2) > thr).any(axis=1)
    runs, start = [], None
    for i, v in enumerate(m):
        if v and start is None:
            start = i
        if not v and start is not None:
            runs.append((start + y0, i - 1 + y0)); start = None
    if start is not None:
        runs.append((start + y0, len(m) - 1 + y0))
    print(runs)


def diff(b, a, out, h):
    B, A = load(b), load(a)
    h = int(h)
    d = np.clip(np.abs(B[:h, :400] - A[:h, :400]) * 4, 0, 255).astype(np.uint8)
    Image.fromarray(d).save(out)


if __name__ == "__main__":
    cmd, *args = sys.argv[1:]
    if cmd == "elements":
        elements(*args)
    elif cmd == "seps":
        seps(args[0], int(args[1]), *map(int, args[2:]))
    elif cmd == "row":
        a = load(args[0]); y, x0, x1 = map(int, args[1:4])
        print([tuple(a[y, x]) for x in range(x0, x1)])
    elif cmd == "col":
        a = load(args[0]); x, y0, y1 = map(int, args[1:4])
        for y in range(y0, y1):
            print(y, tuple(a[y, x]))
    elif cmd == "xruns":
        xruns(args[0], *map(int, args[1:5]), *(map(int, args[5:6])))
    elif cmd == "yruns":
        yruns(args[0], *map(int, args[1:5]), *(map(int, args[5:6])))
    elif cmd == "diff":
        diff(*args)
    elif cmd == "px":
        a = load(args[0]); v = list(map(int, args[1:]))
        for i in range(0, len(v), 2):
            print(v[i], v[i + 1], tuple(a[v[i + 1], v[i]]))
