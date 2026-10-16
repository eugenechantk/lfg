# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Sheet geometry for the app sheet frames (A menu, B subagents, C files/links) and normalised
side-by-sides with the board's sheet. App frames are 3x 1206x2622; the system draws partial
sheets scaled by s (~0.9602) and inset. We find the visible sheet L/R from the surface colour
at y=1500 px and the sheet top T by a column scan, then rescale the app crop by 1/s so 3 px =
1 laid-out sheet pt (same as the 3x board render). Writes scripts/geom.json."""
import os, json
import numpy as np
from PIL import Image, ImageDraw
from lib import E, load

SHEET = np.array([26, 26, 28])
near = lambda c, ref, tol=7: np.abs(c - ref).max() <= tol


def geom(name, ystart):
    a = load(f"app/{name}.png")
    row = a[1500]
    xs = [x for x in range(a.shape[1]) if near(row[x], SHEET)]
    L, R = xs[0], xs[-1]
    col = a[:, 600]
    T = next(y for y in range(ystart, 1500) if col[y].min() > 80) - 14  # grabber top - 14 px
    s = (R - L + 1) / 3 / 402
    return dict(L=int(L), R=int(R), T=int(T), s=s, left_pt=L / 3, top_pt=T / 3, vis_w_pt=(R - L + 1) / 3)


out = {}
starts = {"menu": 300, "subagents": 500, "files": 640, "links": 640}
for name, ys in starts.items():
    g = geom(name, ys)
    out[name] = g
    im = Image.open(os.path.join(E, "app", f"{name}.png")).convert("RGB")
    crop = im.crop((g["L"], g["T"], g["R"] + 1, 2622))
    w = round(crop.width / g["s"]); h = round(crop.height / g["s"])
    crop.resize((w, h), Image.LANCZOS).save(os.path.join(E, "crops", f"app-{name}-sheet-norm.png"))
    print(name, {k: (round(v, 4) if isinstance(v, float) else v) for k, v in g.items()}, "norm", w, h)
json.dump(out, open(os.path.join(E, "scripts", "geom.json"), "w"), indent=1)

boards = {"menu": ("board-menu-appvalues-3x.png", 112), "subagents": ("board-subagents-3x.png", 200),
          "files": ("board-files-3x.png", 200), "links": ("board-links-3x.png", 200)}
for name, (fn, top) in boards.items():
    p = os.path.join(E, "board", fn)
    if not os.path.exists(p):
        continue
    b = Image.open(p).convert("RGB").crop((0, top * 3, 1170, 2532))
    b.save(os.path.join(E, "crops", f"board-{name}-sheet.png"))
    a = Image.open(os.path.join(E, "crops", f"app-{name}-sheet-norm.png"))
    H = max(b.height, a.height)
    sbs = Image.new("RGB", (b.width + a.width + 30, H), (255, 0, 255))
    sbs.paste(b, (0, 0)); sbs.paste(a, (b.width + 30, 0))
    d = ImageDraw.Draw(sbs)
    for yy in range(0, H, 60):  # 20 pt ticks
        d.line([(b.width, yy), (b.width + 30, yy)], fill=(0, 255, 0) if yy % 300 == 0 else (0, 90, 0))
    sbs.save(os.path.join(E, "crops", f"sbs-{name}.png"))
    print("sbs", name, sbs.size)
