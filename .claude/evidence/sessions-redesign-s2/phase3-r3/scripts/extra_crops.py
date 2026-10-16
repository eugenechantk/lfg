# /// script
# dependencies = ["pillow", "numpy"]
# ///
"""Extra native-resolution evidence crops for D (terminal) and E (sign-in) findings."""
import os, glob
import numpy as np
from PIL import Image, ImageDraw
from lib import E

def im(rel):
    return Image.open(os.path.join(E, rel)).convert("RGB")

def sbs(a, b, out, gap=24, label=("board", "app")):
    H = max(a.height, b.height)
    c = Image.new("RGB", (a.width + b.width + gap, H + 22), (255, 0, 255))
    c.paste(a, (0, 22)); c.paste(b, (a.width + gap, 22))
    d = ImageDraw.Draw(c)
    d.rectangle([0, 0, c.width, 21], fill=(240, 240, 240))
    d.text((4, 4), label[0], fill=(0, 0, 0)); d.text((a.width + gap + 4, 4), label[1], fill=(0, 0, 0))
    c.save(os.path.join(E, "crops", out)); print(out, c.size)

# D1 glyph metrics, Fit: board last 4 lines (kb closed) vs app prompt row + 3 empty rows, 0-200 pt wide, 3x
sbs(im("board/board-terminal-kbclosed-fit-3x.png").crop((0, 2140, 600, 2280)), im("app/terminal-fit.png").crop((0, 366, 600, 506)), "D1-fit-glyphs-sbs.png")
# D2 Wide: board Wide tile (page x 0-195, y 422-844) last line vs app Wide prompt row
sbs(im("board/term-wide-kbc-t01.png").crop((0, 900, 585, 1000)), im("app/terminal-wide.png").crop((0, 340, 585, 440)), "D2-wide-glyphs-sbs.png")
# D2 Wide: app status line clipped at the right edge (Fit vs Wide)
sbs(im("app/terminal-fit.png").crop((0, 2370, 1206, 2440)), im("app/terminal-wide.png").crop((0, 2370, 1206, 2440)), "D2-status-fit-vs-wide.png", label=("app Fit", "app Wide"))
# D3 cursor: board cursor vs app cursor at brightest and dimmest frames
fr = sorted(glob.glob(os.path.join(E, "app", "cursorframes", "*.png")))
vals = [(np.asarray(Image.open(f).convert("RGB"))[372:378, 236:246].mean(), f) for f in fr]
hi = max(vals)[1]; lo = min(vals)[1]
print("cursor brightest", os.path.basename(hi), round(max(vals)[0], 1), " dimmest", os.path.basename(lo), round(min(vals)[0], 1))
bc = im("board/board-terminal-kbclosed-fit-3x.png").crop((300, 2180, 460, 2260))
ah = Image.open(hi).convert("RGB").crop((150, 360, 310, 440)); al = Image.open(lo).convert("RGB").crop((150, 360, 310, 440))
c = Image.new("RGB", (160 * 3 + 48, 80), (255, 0, 255)); c.paste(bc, (0, 0)); c.paste(ah, (184, 0)); c.paste(al, (368, 0))
c.save(os.path.join(E, "crops", "D3-cursor-board-appbright-appdim.png")); print("D3 crop", c.size)
# D4 extra key: app key row scrolled to the end, plus the board's full key list (DOM) can't scroll past 390
im("app/terminal-keys-scrolled.png").crop((0, 2470, 1206, 2622)).save(os.path.join(E, "crops", "D4-app-keys-end.png"))
# E1 nav buttons (native 3x): board back/forward vs app back/forward
sbs(im("board/board-signin-appvalues-3x.png").crop((0, 2280, 360, 2460)), im("app/signin.png").crop((0, 2370, 360, 2550)), "E1-nav-buttons-sbs.png")
