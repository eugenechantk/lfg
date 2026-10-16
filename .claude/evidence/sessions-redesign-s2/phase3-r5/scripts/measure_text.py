"""Terminal text metrics: row pitch, cell pitch, cursor block, ink colours, glyph heights."""
import json
import numpy as np
from px import *


def ink_rows(a, x0, y0, x1, y1, thr=90):
    reg = a[y0:y1, x0:x1].mean(axis=2) > thr
    res = []
    for s, e in runs(reg.any(axis=1)):
        xs = np.where(reg[s:e].any(axis=0))[0]
        res.append([s + y0, e + y0, int(xs.min() + x0), int(xs.max() + x0 + 1)])
    return res


def glyph_runs(a, y0, y1, x0, x1, thr=90):
    reg = a[y0:y1, x0:x1].mean(axis=2) > thr
    return [(s + x0, e + x0) for s, e in runs(reg.any(axis=0))]


def top5(a, b):
    reg = a[b[1]:b[3], b[0]:b[2]].reshape(-1, 3)
    lum = reg.mean(axis=1)
    return hexc(np.median(reg[lum >= np.percentile(lum, 95)], axis=0).astype(int))


def cursor_block(a, x0, y0, x1, y1):
    reg = a[y0:y1, x0:x1]
    m = (reg.min(axis=2) > 170) & (np.abs(reg[:, :, 2] - reg[:, :, 0]) < 15)
    # keep columns that are mostly filled (a solid block, not glyph strokes)
    colfill = m.sum(axis=0)
    rr = runs(colfill > 0.6 * colfill.max())
    xs0, xs1 = max(rr, key=lambda t: t[1] - t[0])
    rowfill = m[:, xs0:xs1].sum(axis=1)
    rows = np.where(rowfill > 0.6 * (xs1 - xs0))[0]
    b = (int(xs0 + x0), int(rows.min() + y0), int(xs1 + x0), int(rows.max() + y0 + 1))
    return b, hexc(color_at(a, (b[0] + b[2]) // 2, (b[1] + b[3]) // 2, 3))


res = {}
# ---- app frames ----
for name, f, grid_bottom_pt in [("app_fit_kbup", "app/term-fit-kbup.png", 813.67),
                                 ("app_wide_kbup", "app/term-wide-kbup.png", 813.67),
                                 ("app_fit_kbhidden", "app/term-fit-kbhidden-keystart.png", 778.67),
                                 ("app_wide_kbhidden", "app/term-wide-kbhidden.png", 778.67)]:
    a = load(f)
    r = {}
    rows = ink_rows(a, 36, 120 * 3, 1170, 560 * 3)
    r["rows_pt"] = [pt((x0, y0, x1, y1)) for y0, y1, x0, x1 in rows[:5]]
    # ruler (row 0): glyph runs -> pitch
    y0, y1, _, _ = rows[0]
    g = glyph_runs(a, y0, y1, 30, 1180)
    r["ruler_runs"] = len(g)
    r["ruler_first_last_px"] = (g[0], g[-1])
    if len(g) > 1:
        r["ruler_pitch_pt"] = round((g[-1][0] - g[0][0]) / (len(g) - 1) / 3, 4)
        r["ruler_extent_pt"] = (round(g[0][0] / 3, 2), round(g[-1][1] / 3, 2))
    # row pitch: tops of 'line2' and 'line3' rows (both start with 'l')
    r["pitch_line2_line3_pt"] = round((rows[3][0] - rows[2][0]) / 3, 3)
    r["pitch_ruler1_ruler2_pt"] = round((rows[1][0] - rows[0][0]) / 3, 3)
    # glyph heights: 'line2' ink height (ascender l / digit 2), 'W' cap height
    r["line2_ink_h_pt"] = round((rows[2][1] - rows[2][0]) / 3, 2)
    r["W_ink_h_pt"] = round((rows[0][1] - rows[0][0]) / 3, 2)
    r["text_ink_top5"] = top5(a, (rows[2][2], rows[2][0], rows[2][3], rows[2][1]))
    # cursor block on the prompt row
    py0, py1 = rows[4][0] - 12, rows[4][1] + 12
    cb, cc = cursor_block(a, rows[4][2], py0, rows[4][3] + 10, py1)
    r["cursor_pt"] = pt(cb)
    r["cursor_color"] = cc
    # cursor vs prompt glyph row: block top/bottom relative to 's' x-height row
    r["prompt_row_pt"] = pt((rows[4][2], rows[4][0], rows[4][3], rows[4][1]))
    res[name] = r

# ---- board frames ----
for name, f, fs, lh in [("board_fit_kbo", "board/board-kbo-fit-3x.png", 12, 17.4),
                         ("board_wide_kbo", "board/board-kbo-wide-3x.png", 10.5, 15.225),
                         ("board_fit_kbc", "board/board-kbc-fit-3x.png", 12, 17.4),
                         ("board_wide_kbc", "board/board-kbc-wide-3x.png", 10.5, 15.225)]:
    a = load(f)
    r = {}
    kbo = "kbo" in name
    y_lo, y_hi = (120 * 3, 523 * 3) if kbo else (120 * 3, 759 * 3)
    rows = ink_rows(a, 30, y_lo, 1160, y_hi, thr=70)
    r["n_rows"] = len(rows)
    # " 0 fail" row is 3rd from last
    zf = rows[-3]
    r["zero_fail_ink_h_pt"] = round((zf[1] - zf[0]) / 3, 2)
    r["zero_fail_top5"] = top5(a, (zf[2], zf[0], zf[3], zf[1]))
    r["last_row_bottom_pt"] = round(rows[-1][1] / 3, 2)
    # pitch between the 'eugene@Pro' rows: rows[-1] and rows[-6] (prompt rows 5 apart)
    r["pitch_from_prompt_rows_pt"] = round((rows[-1][0] - rows[-6][0]) / 5 / 3, 3)
    cb, cc = cursor_block(a, 100 * 3, rows[-1][0] - 15, 160 * 3, rows[-1][1] + 15)
    r["cursor_pt"] = pt(cb)
    r["cursor_color"] = cc
    r["prompt_row_pt"] = pt((rows[-1][2], rows[-1][0], rows[-1][3], rows[-1][1]))
    # first-column glyph left edge (e of eugene) and 'M' cap height on " M ios" row
    mrow = rows[2]
    r["M_row_ink_h_pt"] = round((mrow[1] - mrow[0]) / 3, 2)
    res[name] = r

json.dump(res, open(E + "/text-measures.json", "w"), indent=1)
for k, v in res.items():
    print("==", k)
    for kk, vv in v.items():
        print("   ", kk, vv)
