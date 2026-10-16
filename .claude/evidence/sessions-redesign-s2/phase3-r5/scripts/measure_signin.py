"""Board E (s2-signin) vs app sign-in browser. y relative to the sheet top (board 54, app 62);
bottom items from the screen bottom (844 / 874); right items by right inset (390 / 402)."""
import json
import numpy as np
from px import *

SHEET = (28, 28, 30)
out = {}


def measure(a, top, H, W):
    r = {}
    T = int(top * 3)
    # sheet top edge at screen centre
    col = a[(top - 10) * 3:(top + 10) * 3, int(W / 2 * 3)]
    k = int(np.argmax(np.abs(col - np.array([0, 0, 0])).max(axis=1) > 10))
    st = (top - 10) * 3 + k
    r["sheet_top_px_pt"] = round(st / 3, 2)
    r["sheet_fill"] = hexc(color_at(a, int(W / 2 * 3), st + 12))
    # corner: left inset of sheet fill on rows below the top edge (px)
    prof = []
    for kk in (0, 3, 6, 12, 24, 48, 72, 96, 114):
        row = np.abs(a[st + kk, :200] - np.array([0, 0, 0])).max(axis=1) > 10
        idx = np.where(row)[0]
        prof.append((kk, int(idx[0]) if len(idx) else None))
    r["sheet_corner_profile_px"] = prof
    # close circle (fill #2C2C2E vs sheet #1C1C1E) in x 0..60, y top+5..top+55
    sheet = color_at(a, int(W / 2 * 3), st + 12)
    cb = bbox_diff(a, 3 * 3, T + 9 * 3, 56 * 3, T + 55 * 3, sheet, 8)
    r["close"] = pt(cb, 0, top)
    r["close_fill"] = hexc(color_at(a, cb[0] + 9, (cb[1] + cb[3]) // 2))
    g = bbox_bright(a, cb[0] + 6, cb[1] + 6, cb[2] - 6, cb[3] - 6, 120)
    r["close_glyph"] = pt(g, 0, top)
    r["close_glyph_color"] = hexc(color_at(a, (g[0] + g[2]) // 2, (g[1] + g[3]) // 2, 1))
    # reload circle at the right
    rb = bbox_diff(a, int((W - 56) * 3), T + 9 * 3, int((W - 3) * 3), T + 55 * 3, sheet, 8)
    r["reload"] = pt(rb, 0, top)
    r["reload_right_inset"] = round(W - rb[2] / 3, 2)
    rg = bbox_bright(a, rb[0] + 6, rb[1] + 6, rb[2] - 6, rb[3] - 6, 120)
    r["reload_glyph"] = pt(rg, 0, top)
    r["reload_glyph_rel_circle"] = (round((rg[0] - rb[0]) / 3, 2), round((rg[1] - rb[1]) / 3, 2))
    # address pill between them
    pb = bbox_diff(a, cb[2] + 3, T + 9 * 3, rb[0] - 3, T + 55 * 3, sheet, 8)
    r["pill"] = pt(pb, 0, top)
    r["pill_right_inset"] = round(W - pb[2] / 3, 2)
    r["pill_fill"] = hexc(color_at(a, pb[0] + 15, (pb[1] + pb[3]) // 2))
    # pill corner radius: rows from top until the left column is filled
    r["pill_corner_rows_px"] = corner_radius_px(a, pb[0], pb[1], sheet, 8)
    # line 1 (lock + host): bright-ish ink in the upper half of the pill
    y_mid = (pb[1] + pb[3]) // 2
    l1 = bbox_lum(a, pb[0] + 6, pb[1] + 3, pb[2] - 6, y_mid + 3, 110)
    r["line1_ink"] = pt(l1, 0, top)
    r["line1_cx_off"] = round((l1[0] + l1[2]) / 6 - (pb[0] + pb[2]) / 6, 2)
    # lock icon: first ink column run of line 1
    reg = a[l1[1]:l1[3], l1[0]:l1[2]].mean(axis=2) > 110
    cr = runs(reg.any(axis=0))
    lock = (l1[0] + cr[0][0], l1[1], l1[0] + cr[0][1], l1[3])
    lk = bbox_lum(a, lock[0], pb[1] + 3, lock[2], y_mid + 3, 90)
    r["lock_icon"] = pt(lk, 0, top)
    r["lock_color"] = hexc(np.median(a[lk[1]:lk[3], lk[0]:lk[2]].reshape(-1, 3)[a[lk[1]:lk[3], lk[0]:lk[2]].reshape(-1, 3).mean(axis=1) > 120], axis=0).astype(int))
    host = bbox_lum(a, cr[1][0] + l1[0], pb[1] + 3, l1[2], y_mid + 3, 110)
    r["host_ink"] = pt(host, 0, top)
    r["lock_to_host_gap"] = round((host[0] - lk[2]) / 3, 2)
    hreg = a[host[1]:host[3], host[0]:host[2]].reshape(-1, 3)
    r["host_color_top5"] = hexc(np.median(hreg[hreg.mean(axis=1) >= np.percentile(hreg.mean(axis=1), 95)], axis=0).astype(int))
    # line 2 (orange subtitle): R high, B low
    reg = a[y_mid - 3:pb[3] - 2, pb[0] + 6:pb[2] - 6]
    om = (reg[:, :, 0] > 120) & (reg[:, :, 0] - reg[:, :, 2] > 60)
    sb = bbox_mask(om, pb[0] + 6, y_mid - 3)
    r["subtitle_ink"] = pt(sb, 0, top)
    r["subtitle_cx_off"] = round((sb[0] + sb[2]) / 6 - (pb[0] + pb[2]) / 6, 2)
    sreg = a[sb[1]:sb[3], sb[0]:sb[2]].reshape(-1, 3)
    r["subtitle_color_top5"] = hexc(np.median(sreg[sreg[:, 0] >= np.percentile(sreg[:, 0], 95)], axis=0).astype(int))
    # web content region: column x=5 from the header down / from the bottom up
    colw = a[:, 5 * 3]
    ys = [y for y in range(T + 50 * 3, int((H - 50) * 3)) if np.abs(colw[y] - np.array(sheet)).max() > 3]
    r["web_top"] = round(ys[0] / 3 - top, 2)
    r["web_bottom_from_screen"] = round(H - (ys[-1] + 1) / 3, 2)
    r["web_bg_sample"] = hexc(color_at(a, 5 * 3, ys[0] + 30))
    # bottom bar
    Bt = int((H - 80) * 3)
    bb = bbox_diff(a, 0, Bt, 58 * 3, int((H - 20) * 3), sheet, 8)
    fb = bbox_diff(a, 58 * 3, Bt, 110 * 3, int((H - 20) * 3), sheet, 8)
    db = bbox_diff(a, 110 * 3, Bt, int(W * 3), int((H - 20) * 3), sheet, 40)
    for nm, b in (("back", bb), ("forward", fb), ("done", db)):
        r[nm] = pt(b)
        r[nm + "_bottom_from_screen"] = round(H - b[3] / 3, 2)
        r[nm + "_right_inset"] = round(W - b[2] / 3, 2)
        r[nm + "_fill"] = hexc(color_at(a, b[0] + 12, (b[1] + b[3]) // 2))
    for nm, b in (("back", bb), ("forward", fb)):
        reg = a[b[1] + 6:b[3] - 6, b[0] + 6:b[2] - 6]
        fill = np.array(color_at(a, b[0] + 12, (b[1] + b[3]) // 2))
        m = np.abs(reg - fill).max(axis=2) > 25
        gb = bbox_mask(m, b[0] + 6, b[1] + 6)
        r[nm + "_glyph"] = pt(gb)
        r[nm + "_glyph_rel"] = (round((gb[0] - b[0]) / 3, 2), round((gb[1] - b[1]) / 3, 2))
        greg = a[gb[1]:gb[3], gb[0]:gb[2]].reshape(-1, 3)
        r[nm + "_glyph_color_top5"] = hexc(np.median(greg[greg.mean(axis=1) >= np.percentile(greg.mean(axis=1), 97)], axis=0).astype(int))
    lab = bbox_bright(a, db[0] + 12, db[1] + 6, db[2] - 12, db[3] - 6, 200)
    r["done_label"] = pt(lab)
    r["done_label_cx_off"] = round((lab[0] + lab[2]) / 6 - (db[0] + db[2]) / 6, 2)
    r["done_label_cy_off"] = round((lab[1] + lab[3]) / 6 - (db[1] + db[3]) / 6, 2)
    r["done_corner_rows_px"] = corner_radius_px(a, db[0], db[1], sheet, 40, depth=90)
    return r


B = load("board/board-signin-3x.png")
A = load("app/signin.png")
rb, ra = measure(B, 54, 844, 390), measure(A, 62, 874, 402)
json.dump({"board": rb, "app": ra}, open(E + "/signin-measures.json", "w"), indent=1)
for k in rb:
    print(f"{k:26s} board {rb[k]}  |  app {ra[k]}")
