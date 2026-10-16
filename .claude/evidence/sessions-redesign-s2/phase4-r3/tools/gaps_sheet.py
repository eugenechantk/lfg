"""Evidence sheets for the gap round.
1. gaps/titleband-x3.png: top 100pt of board | harness (off-screen) | on-screen active | on-screen inactive, nearest x3.
2. gaps/click-fold-x2.png: header region y=84..320 of on-screen before | after 1st click | after 2nd click, plus board open | board fold-working, x2.
"""
import os

from PIL import Image, ImageDraw

R = "/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase4-r3"
os.chdir(R)


def strip(items, box, k, out):
    x0, y0, x1, y1 = box
    w, h = (x1 - x0) * k, (y1 - y0) * k
    sheet = Image.new("RGB", (w, len(items) * (h + 16)), (90, 0, 90))
    d = ImageDraw.Draw(sheet)
    for i, (label, path) in enumerate(items):
        im = Image.open(path).convert("RGB").crop(box).resize((w, h), Image.NEAREST)
        sheet.paste(im, (0, i * (h + 16) + 14))
        d.text((3, i * (h + 16) + 1), label, fill=(255, 255, 255))
    sheet.save(out)
    print(out, sheet.size)


strip([("board", "board-open.png"), ("harness off-screen (inactive)", "app-open-srgb.png"),
       ("on-screen ACTIVE, current build, live data", "gaps/active-before-click-srgb.png"),
       ("on-screen INACTIVE, current build, live data", "gaps/inactive-srgb.png")],
      (0, 0, 400, 100), 3, "gaps/titleband-x3.png")
strip([("on-screen before click", "gaps/active-before-click-srgb.png"),
       ("on-screen after 1st click on Working header", "gaps/after-click-folded-srgb.png"),
       ("on-screen after 2nd click", "gaps/after-second-click-open-srgb.png"),
       ("board open (reference behaviour)", "board-open.png"),
       ("board after clicking Working (reference behaviour)", "board-fold-working.png")],
      (0, 84, 400, 320), 2, "gaps/click-fold-x2.png")
