"""Selected (black on white) label ink inside the thumb, excluding the capsule's corners."""
from px import *

for name, bf, af, bth, ath in [("Fit", "board/board-kbc-fit-3x.png", "app/term-fit-kbup.png", (288, 66), (300, 74)),
                               ("Wide", "board/board-kbc-wide-3x.png", "app/term-wide-kbup.png", (332, 66), (344, 74))]:
    for tag, f, (x, y), top in [("board", bf, bth, 54), ("app", af, ath, 62)]:
        a = load(f)
        x0, y0, x1, y1 = int((x + 8) * 3), int((y + 4) * 3), int((x + 36) * 3), int((y + 24) * 3)
        reg = a[y0:y1, x0:x1]
        b = bbox_mask(reg.max(axis=2) < 140, x0, y0)
        print(name, tag, "label ink", pt(b, 0, top), "cx off in thumb", round((b[0] + b[2]) / 6 - (x + 22), 2),
              "cy off", round((b[1] + b[3]) / 6 - (y + 14), 2), "ink colour", hexc(color_at(a, 0, 0, 0)) if False else "")
