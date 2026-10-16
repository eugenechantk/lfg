"""Measure board D (s2-terminal) vs app terminal frames. Prints pt values.
Page-relative y: board origin 54pt, app 62pt. Bottom-relative: 844 / 874.
Right insets: 390 / 402."""
import json, sys
import numpy as np
from px import *

BG = (11, 11, 13)
ROWBG = (28, 28, 30)
out = {}


def header(a, top, W, tag):
    """top/W in pt. Returns dict of pt measures (y page-relative, x left or right inset)."""
    r = {}
    T = int(top * 3)
    # close circle: non-bg in x 0..70pt, y top..top+52
    b = bbox_diff(a, 0, T, 70 * 3, T + 52 * 3, BG, 12)
    r["close_circle"] = pt(b, 0, top)
    cx0, cy0, cx1, cy1 = b
    g = bbox_bright(a, cx0, cy0, cx1, cy1, 200)
    r["close_x_glyph"] = pt(g, 0, top)
    r["close_fill"] = hexc(color_at(a, cx0 + 12, (cy0 + cy1) // 2))
    # title: bright ink in centre band
    t = bbox_bright(a, 90 * 3, T + 4 * 3, int((W - 120) * 3), T + 27 * 3, 150)
    r["title_ink"] = pt(t, 0, top)
    r["title_cx"] = round((t[0] + t[2]) / 6 - W / 2, 2)
    s = bbox_lum(a, 70 * 3, T + 27 * 3, int((W - 105) * 3), T + 46 * 3, 70)
    r["subtitle_ink"] = pt(s, 0, top)
    r["subtitle_cx"] = round((s[0] + s[2]) / 6 - W / 2, 2)
    # subtitle colour: brightest 5% of ink pixels
    reg = a[s[1]:s[3], s[0]:s[2]].reshape(-1, 3)
    lum = reg.mean(axis=1)
    r["subtitle_ink_top5pct"] = hexc(np.median(reg[lum >= np.percentile(lum, 95)], axis=0).astype(int))
    reg = a[t[1]:t[3], t[0]:t[2]].reshape(-1, 3)
    lum = reg.mean(axis=1)
    r["title_ink_top5pct"] = hexc(np.median(reg[lum >= np.percentile(lum, 95)], axis=0).astype(int))
    # segmented control: non-bg in x W-110..W
    sg = bbox_diff(a, int((W - 110) * 3), T, int(W * 3), T + 52 * 3, BG, 12)
    r["seg_outer"] = pt(sg, 0, top)
    r["seg_outer_right_inset"] = round(W - sg[2] / 3, 2)
    th = bbox_bright(a, sg[0], sg[1], sg[2], sg[3], 235)
    r["seg_thumb"] = pt(th, 0, top)
    r["seg_thumb_right_inset"] = round(W - th[2] / 3, 2)
    r["seg_track"] = hexc(color_at(a, (sg[0] + 6) if th[0] - sg[0] > 30 else (sg[2] - 6), (sg[1] + sg[3]) // 2))
    # label inside thumb: dark ink
    reg = a[th[1] + 6:th[3] - 6, th[0] + 6:th[2] - 6]
    r["seg_selected_label_ink"] = pt(bbox_mask(reg.max(axis=2) < 110, th[0] + 6, th[1] + 6), 0, top)
    # unselected label: bright ink outside thumb
    if th[0] - sg[0] > 30:  # thumb on the right -> label on left
        ux0, ux1 = sg[0] + 9, th[0] - 3
    else:
        ux0, ux1 = th[2] + 3, sg[2] - 9
    r["seg_unselected_label_ink"] = pt(bbox_bright(a, ux0, sg[1] + 9, ux1, sg[3] - 9, 150), 0, top)
    # track radius: rows from top of outer until its left edge column filled
    r["seg_outer_radius_px"] = corner_radius_px(a, sg[0], sg[1], BG, 12)
    r["seg_thumb_radius_px"] = corner_radius_px(a, th[0], th[1], (49, 49, 50), 60)
    return r


def keyrow(a, H, W, row_top_guess_pt, tag):
    """H/W screen pt. Returns row bounds, keys (pt, x left), labels."""
    r = {}
    y0 = int((row_top_guess_pt - 12) * 3)
    col = a[y0:y0 + 30 * 3, 4 * 3]
    # border = first pixel that is not page bg after page bg
    diff = np.abs(col - np.array(BG)).max(axis=1) > 8
    k = int(np.argmax(diff))
    top = y0 + k
    r["row_top_px"] = top
    r["row_top_from_bottom"] = round(H - top / 3, 2)
    r["border_color"] = hexc(a[top, 12])
    r["row_bg"] = hexc(color_at(a, 4 * 3, top + 20))
    # keys: along key mid line, fill differs from row bg
    mid = top + 25 * 3
    line = np.abs(a[mid, :] - np.array(r_bg := color_at(a, 4 * 3, top + 20))).max(axis=1) > 14
    ks = [(s, e) for s, e in runs(line) if e - s > 20]
    keys = []
    for s, e in ks:
        cx = (s + e) // 2
        c = np.abs(a[top:top + 52 * 3, cx] - np.array(r_bg)).max(axis=1) > 14
        vr = [(vs, ve) for vs, ve in runs(c) if ve - vs > 60]
        vs, ve = vr[0]
        kb = (s, top + vs, e, top + ve)
        lab = bbox_bright(a, s + 6, top + vs + 6, e - 6, top + ve - 6, 150)
        keys.append({"key": pt(kb), "right_inset": round(W - e / 3, 2),
                     "top_below_row": round(vs / 3, 2), "bottom_from_screen": round(H - (top + ve) / 3, 2),
                     "label_ink": pt(lab), "fill": hexc(color_at(a, s + 8, top + vs + 50)),
                     "radius_px": corner_radius_px(a, s, top + vs, r_bg, 14)})
    r["keys"] = keys
    return r


def term_grid(a, top, H, keyrow_top_px):
    """App only: status bar (green) gives grid width/left/bottom; ruler gives pitch."""
    r = {}
    g = (a[:, :, 1] > 150) & (a[:, :, 0] < 90) & (a[:, :, 2] < 90)
    gb = bbox_mask(g[: keyrow_top_px])
    r["status_bar"] = pt(gb, 0, top)
    r["status_bar_bottom_gap_to_row"] = round((keyrow_top_px - gb[3]) / 3, 2)
    return r


def text_rows(a, x0, y0, x1, y1, thr=120):
    """Ink rows (bright pixels) -> list of (y0,y1,x0,x1) px."""
    reg = a[y0:y1, x0:x1].mean(axis=2) > thr
    res = []
    for s, e in runs(reg.any(axis=1)):
        xs = np.where(reg[s:e].any(axis=0))[0]
        res.append((s + y0, e + y0, int(xs.min() + x0), int(xs.max() + x0 + 1)))
    return res


def cursor(a, x0, y0, x1, y1):
    reg = a[y0:y1, x0:x1]
    m = (np.abs(reg - np.array([209, 209, 214])).max(axis=2) < 22)
    # largest solid block: rows where >= 12 px are cursor-coloured consecutively
    b = bbox_mask(m, x0, y0)
    return b, (hexc(color_at(a, (b[0] + b[2]) // 2, (b[1] + b[3]) // 2, 3)) if b else None)


if __name__ == "__main__":
    BW, BH, AW, AH = 390, 844, 402, 874
    pairs = {
        "fit_kbup": ("board/board-kbo-fit-3x.png", "app/term-fit-kbup.png", 524, 824),
        "wide_kbup": ("board/board-kbo-wide-3x.png", "app/term-wide-kbup.png", 524, 824),
        "fit_kbhidden": ("board/board-kbc-fit-3x.png", "app/term-fit-kbhidden-keystart.png", 760, 790),
        "wide_kbhidden": ("board/board-kbc-wide-3x.png", "app/term-wide-kbhidden.png", 760, 790),
        "fit_kbup_keysend": ("board/board-kbc-fit-keysend-3x.png", "app/term-fit-kbup-keysend.png", 760, 824),
    }
    for name, (bf, af, brt, art) in pairs.items():
        B, A = load(bf), load(af)
        res = {"board": {}, "app": {}}
        res["board"]["header"] = header(B, 54, BW, "b")
        res["app"]["header"] = header(A, 62, AW, "a")
        res["board"]["keyrow"] = keyrow(B, BH, BW, brt, "b")
        res["app"]["keyrow"] = keyrow(A, AH, AW, art, "a")
        res["app"]["grid"] = term_grid(A, 62, AH, res["app"]["keyrow"]["row_top_px"])
        out[name] = res
    json.dump(out, open(E + "/term-measures.json", "w"), indent=1)
    for name, res in out.items():
        print("=====", name)
        for part in ("header",):
            for k in res["board"][part]:
                print(f"  {k:28s} board {res['board'][part][k]}  |  app {res['app'][part][k]}")
        bk, ak = res["board"]["keyrow"], res["app"]["keyrow"]
        for k in ("row_top_from_bottom", "border_color", "row_bg"):
            print(f"  {k:28s} board {bk[k]}  |  app {ak[k]}")
        print("  board keys:")
        for kk in bk["keys"]:
            print("    ", kk)
        print("  app keys:")
        for kk in ak["keys"]:
            print("    ", kk)
        print("  app grid", res["app"]["grid"])
