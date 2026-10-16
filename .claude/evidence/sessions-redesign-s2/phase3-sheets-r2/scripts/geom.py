# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Sheet geometry for app frames + normalised side-by-sides.

App frames are 3x (1206x2622). The system sheet is scaled ~0.96 and inset; this finds its
visible left/right/top edges from the sheet surface colour, computes s = visible width / 402,
and writes a normalised crop where 3 px = 1 laid-out sheet pt (so it lines up with the 3x
board render of the board's sheet).

usage: geom.py <evidence_dir>
"""
import sys, os, json
import numpy as np
from PIL import Image, ImageDraw

E = sys.argv[1]
SHEET = np.array([26, 26, 28])


def load(p):
    return np.asarray(Image.open(p).convert("RGB")).astype(int)


def near(c, ref, tol=7):
    return np.abs(c - ref).max() <= tol


def geom(path, ystart=250):
    # files/links: a dimmed transcript file card sits behind the sheet at y 485-616 px with a
    # near-sheet colour, so their search starts below it (verified by a vertical scan at x=300).
    a = load(path)
    y = 1500
    row = a[y]
    xs = [x for x in range(a.shape[1]) if near(row[x], SHEET)]
    L, R = xs[0], xs[-1]
    col = a[:, 300]
    T = next(yy for yy in range(ystart, 1500) if near(col[yy], SHEET) and near(col[yy + 3], SHEET))
    s = (R - L + 1) / 3 / 402
    return dict(L=L, R=R, T=T, s=s, left_pt=L / 3, top_pt=T / 3, vis_w_pt=(R - L + 1) / 3)


out = {}
for name in ["menu", "subagents", "files", "links"]:
    g = geom(os.path.join(E, "app", f"{name}.png"), 630 if name in ("files", "links") else 250)
    out[name] = g
    im = Image.open(os.path.join(E, "app", f"{name}.png")).convert("RGB")
    crop = im.crop((g["L"], g["T"], g["R"] + 1, 2622))
    w = round(crop.width / g["s"]); h = round(crop.height / g["s"])
    crop.resize((w, h), Image.LANCZOS).save(os.path.join(E, "crops", f"app-{name}-sheet-norm.png"))
    print(name, json.dumps({k: round(v, 4) if isinstance(v, float) else v for k, v in g.items()}), "norm size", w, h)
json.dump(out, open(os.path.join(E, "scripts", "geom.json"), "w"), indent=1)

boards = {"menu": ("board-menu-longhost-3x.png", 112), "subagents": ("board-subagents-3x.png", 200), "files": ("board-files-3x.png", 200)}
for name, (fn, top) in boards.items():
    b = Image.open(os.path.join(E, "board", fn)).convert("RGB").crop((0, top * 3, 1170, 2532))
    b.save(os.path.join(E, "crops", f"board-{name}-sheet.png"))
    a = Image.open(os.path.join(E, "crops", f"app-{name}-sheet-norm.png"))
    H = max(b.height, a.height)
    sbs = Image.new("RGB", (b.width + a.width + 30, H), (255, 0, 255))
    sbs.paste(b, (0, 0)); sbs.paste(a, (b.width + 30, 0))
    d = ImageDraw.Draw(sbs)
    for yy in range(0, H, 60):  # 20pt grid ticks
        d.line([(b.width, yy), (b.width + 30, yy)], fill=(0, 255, 0) if yy % 300 == 0 else (0, 90, 0))
    sbs.save(os.path.join(E, "crops", f"sbs-{name}.png"))
    print("sbs", name, sbs.size)
