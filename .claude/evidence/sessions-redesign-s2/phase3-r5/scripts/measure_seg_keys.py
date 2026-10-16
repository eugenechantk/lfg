"""Segmented control detail, key-row end (keysend), keyboard-key icon, key corner profile."""
import numpy as np
from px import *

BG = np.array([11, 11, 13])


def seg(a, top, W):
    T = int(top * 3)
    sg = bbox_diff(a, int((W - 110) * 3), T, int(W * 3), T + 52 * 3, BG, 12)
    y = sg[1] + 9  # 3pt below the track top, above the labels
    line = a[y, sg[0]:sg[2]].min(axis=1) > 235
    rr = max(runs(line), key=lambda t: t[1] - t[0])
    tx0, tx1 = sg[0] + rr[0], sg[0] + rr[1]
    col = a[sg[1]:sg[3], tx0 + 30].min(axis=1) > 235
    vr = max(runs(col), key=lambda t: t[1] - t[0])
    th = (tx0, sg[1] + vr[0], tx1, sg[1] + vr[1])
    reg = a[th[1]:th[3], th[0] + 6:th[2] - 6]
    sel = bbox_mask(reg.max(axis=2) < 120, th[0] + 6, th[1])
    if th[0] - sg[0] > 30:
        ux0, ux1 = sg[0] + 6, th[0] - 3
    else:
        ux0, ux1 = th[2] + 3, sg[2] - 6
    uns = bbox_bright(a, ux0, sg[1] + 6, ux1, sg[3] - 6, 150)
    return {"outer": pt(sg, 0, top), "thumb": pt(th, 0, top), "thumb_gap_l": round((th[0] - sg[0]) / 3, 2),
            "thumb_gap_r": round((sg[2] - th[2]) / 3, 2), "sel_label": pt(sel, 0, top),
            "sel_label_cx_in_thumb": round(((sel[0] + sel[2]) / 2 - (th[0] + th[2]) / 2) / 3, 2),
            "uns_label": pt(uns, 0, top), "uns_label_color": hexc(color_at(a, (uns[0] + uns[2]) // 2, (uns[1] + uns[3]) // 2, 0))}


def corner_profile(a, x0, y0, bg, n=27):
    """Left inset (px) of the key fill on each of the first n rows from its top edge."""
    prof = []
    for k in range(n):
        row = np.abs(a[y0 + k, x0:x0 + 40] - np.array(bg)).max(axis=1) > 14
        idx = np.where(row)[0]
        prof.append(int(idx[0]) if len(idx) else None)
    return prof


for name, bf, af, btop, atop in [("Fit", "board/board-kbc-fit-3x.png", "app/term-fit-kbup.png", 54, 62),
                                 ("Wide", "board/board-kbc-wide-3x.png", "app/term-wide-kbup.png", 54, 62)]:
    B, A = load(bf), load(af)
    print("== seg", name)
    sb, sa = seg(B, btop, 390), seg(A, atop, 402)
    for k in sb:
        print(f"   {k:22s} board {sb[k]}  |  app {sa[k]}")

# key row end
print("== key row end (keysend)")
for tag, f, H, W, rowtop in [("board kbc keysend", "board/board-kbc-fit-keysend-3x.png", 844, 390, 760),
                             ("board kbo keysend tile", None, 844, 390, 524),
                             ("app kbup keysend", "app/term-fit-kbup-keysend.png", 874, 402, 824),
                             ("app kbhidden (wide)", "app/term-wide-kbhidden.png", 874, 402, 789)]:
    if f is None:
        # kb-open keysend tile covers board x 195..390, y 422..844
        from PIL import Image
        t = np.asarray(Image.open(E + "/board/kbo-wide-keysend-t11.png").convert("RGB")).astype(int)
        a = np.zeros((2532, 1170, 3), dtype=int); a[1266:, 585:] = t
    else:
        a = load(f)
    top = int(rowtop * 3)
    # find exact row top on a column near the right edge (x = W-4)
    col = np.abs(a[top - 30:top + 30, int((W - 4) * 3)] - BG).max(axis=1) > 8
    top = top - 30 + int(np.argmax(col))
    rbg = color_at(a, int((W - 4) * 3), top + 20)
    mid = top + 25 * 3
    line = np.abs(a[mid, :] - np.array(rbg)).max(axis=1) > 14
    ks = [(s, e) for s, e in runs(line) if e - s > 20]
    print(f"  {tag}: row top {round(top/3,2)} (from bottom {round(H-top/3,2)}), row bg {hexc(rbg)}")
    for s, e in ks[-4:]:
        cx = (s + e) // 2
        c = np.abs(a[top:top + 52 * 3, cx] - np.array(rbg)).max(axis=1) > 14
        vs, ve = max(runs(c), key=lambda t: t[1] - t[0])
        lab = bbox_bright(a, s + 6, top + vs + 6, e - 6, top + ve - 6, 150)
        print(f"     key x {round(s/3,2)}..{round(e/3,2)} w {round((e-s)/3,2)} right_inset {round(W-e/3,2)} y {round((top+vs)/3,2)}..{round((top+ve)/3,2)} | label {pt(lab)} label_rel_key ({round((lab[0]-s)/3,2)},{round((lab[1]-top-vs)/3,2)})")
    # icon in the last key: bright ink
    s, e = ks[-1]
    cx = (s + e) // 2
    c = np.abs(a[top:top + 52 * 3, cx] - np.array(rbg)).max(axis=1) > 14
    vs, ve = max(runs(c), key=lambda t: t[1] - t[0])
    ib = bbox_bright(a, s + 3, top + vs + 3, e - 3, top + ve - 3, 120)
    reg = a[ib[1]:ib[3], ib[0]:ib[2]].mean(axis=2) > 120
    # arrow chevron = ink rows below the keyboard outline rect; report lowest 5 rows' ink centre
    rows_ink = [int(r.sum()) for r in reg]
    print(f"     icon bbox {pt(ib)} rel key ({round((ib[0]-s)/3,2)},{round((ib[1]-top-vs)/3,2)}) size {round((ib[2]-ib[0])/3,2)}x{round((ib[3]-ib[1])/3,2)}")
    print(f"     icon row ink profile (px rows, count): {rows_ink}")

print("== key corner profile (esc key, first 27 px rows): left inset px")
for tag, f, x0, rowtop in [("board", "board/board-kbc-fit-3x.png", 8, 760), ("app", "app/term-fit-kbhidden-keystart.png", 8, 789)]:
    a = load(f)
    top = int(rowtop * 3)
    col = np.abs(a[top - 30:top + 30, 12] - BG).max(axis=1) > 8
    top = top - 30 + int(np.argmax(col))
    rbg = color_at(a, 12, top + 20)
    cx = int((x0 + 20) * 3)
    c = np.abs(a[top:top + 52 * 3, cx] - np.array(rbg)).max(axis=1) > 14
    vs, ve = max(runs(c), key=lambda t: t[1] - t[0])
    print("  ", tag, "key top px", top + vs, corner_profile(a, int(x0 * 3) - 3, top + vs, rbg))
