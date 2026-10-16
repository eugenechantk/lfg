"""Segmented Fit/Wide control: thumb bbox per half, label ink per half."""
import numpy as np
from px import *

BG = np.array([11, 11, 13])
for name, bf, af in [("Fit selected", "board/board-kbc-fit-3x.png", "app/term-fit-kbup.png"),
                     ("Wide selected", "board/board-kbc-wide-3x.png", "app/term-wide-kbup.png")]:
    print("==", name)
    for tag, f, top, W in [("board", bf, 54, 390), ("app", af, 62, 402)]:
        a = load(f)
        T = int(top * 3)
        sg = bbox_diff(a, int((W - 110) * 3), T, int(W * 3), T + 52 * 3, BG, 12)
        midx = (sg[0] + sg[2]) // 2
        halves = {"left": (sg[0], midx), "right": (midx, sg[2])}
        out = {"outer": pt(sg, 0, top)}
        for h, (x0, x1) in halves.items():
            white = a[sg[1]:sg[3], x0:x1].min(axis=2) > 235
            frac = white.mean()
            if frac > 0.4:  # this half holds the thumb
                tb = bbox_mask(white, x0, sg[1])
                lab = bbox_mask(a[tb[1]:tb[3], tb[0]:tb[2]].max(axis=2) < 120, tb[0], tb[1])
                out[h + "_thumb"] = pt(tb, 0, top)
                out[h + "_thumb_insets_lrtb"] = (round((tb[0] - sg[0]) / 3, 2) if h == "left" else round((tb[0] - midx) / 3, 2),
                                                 round((sg[2] - tb[2]) / 3, 2) if h == "right" else round((midx - tb[2]) / 3, 2),
                                                 round((tb[1] - sg[1]) / 3, 2), round((sg[3] - tb[3]) / 3, 2))
                out[h + "_label_dark"] = pt(lab, 0, top)
                out[h + "_label_cx_off"] = round(((lab[0] + lab[2]) / 2 - (tb[0] + tb[2]) / 2) / 3, 2)
                out[h + "_label_cy_off"] = round(((lab[1] + lab[3]) / 2 - (tb[1] + tb[3]) / 2) / 3, 2)
            else:
                lab = bbox_bright(a, x0, sg[1] + 3, x1, sg[3] - 3, 150)
                out[h + "_label_white"] = pt(lab, 0, top)
                out[h + "_label_cx_off_in_half"] = round(((lab[0] + lab[2]) / 2 - (x0 + x1) / 2) / 3, 2)
                out[h + "_label_cy_off"] = round(((lab[1] + lab[3]) / 2 - (sg[1] + sg[3]) / 2) / 3, 2)
                out[h + "_track"] = hexc(color_at(a, x0 + 9, (sg[1] + sg[3]) // 2, 1))
        print("  ", tag, out)
