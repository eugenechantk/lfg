"""Write ../pairs.json for prepare_evidence.py (rects in pt, 3 px per pt; from measured frames)."""
import json, os

E = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
S = {
    "b_kbo_fit": ("board/board-kbo-fit-3x.png", [390, 844]),
    "b_kbo_wide": ("board/board-kbo-wide-3x.png", [390, 844]),
    "b_kbc_fit": ("board/board-kbc-fit-3x.png", [390, 844]),
    "b_kbc_wide": ("board/board-kbc-wide-3x.png", [390, 844]),
    "b_kbc_fit_keysend": ("board/board-kbc-fit-keysend-3x.png", [390, 844]),
    "b_kbo_keysend_tile": ("board/kbo-wide-keysend-t11.png", [195, 422]),
    "b_signin": ("board/board-signin-3x.png", [390, 844]),
    "a_fit_kbup": ("app/term-fit-kbup.png", [402, 874]),
    "a_fit_kbup_keysend": ("app/term-fit-kbup-keysend.png", [402, 874]),
    "a_wide_kbup": ("app/term-wide-kbup.png", [402, 874]),
    "a_fit_kbhidden": ("app/term-fit-kbhidden-keystart.png", [402, 874]),
    "a_wide_kbhidden": ("app/term-wide-kbhidden.png", [402, 874]),
    "a_signin": ("app/signin.png", [402, 874]),
}
sources = {k: {"path": v[0], "pixels_per_unit": 3, "viewport": v[1]} for k, v in S.items()}
pairs = []


def P(id_, state, bs, br, as_, ar):
    pairs.append({"id": id_ + "__" + state, "state": state, "design": {"source": bs, "rect": br}, "app": {"source": as_, "rect": ar}})


for st, b, a in [("fit-kbup", "b_kbo_fit", "a_fit_kbup"), ("wide-kbup", "b_kbo_wide", "a_wide_kbup"),
                 ("fit-kbhidden", "b_kbc_fit", "a_fit_kbhidden"), ("wide-kbhidden", "b_kbc_wide", "a_wide_kbhidden")]:
    P("D-full", st, b, [0, 0, 390, 844], a, [0, 0, 402, 874])
    P("D-close", st, b, [8, 54, 52, 52], a, [8, 62, 52, 52])
    P("D-title", st, b, [60, 58, 222, 44], a, [60, 66, 234, 44])
    P("D-segmented", st, b, [282, 60, 100, 40], a, [294, 68, 100, 40])
    if "kbup" in st:
        fit = "fit" in st
        P("D-text-rows", st, b, [0, 440, 200, 84], a, [0, 130, 200, 100])
        P("D-cursor", st, b, [100, 494, 50, 22] if fit else [100, 496, 40, 20], a, [50, 202, 40, 22] if fit else [50, 187, 40, 20])
        P("D-text-bottom-gap", st, b, [0, 494, 390, 36], a, [0, 792, 402, 36])
        P("D-keyrow-start", st, b, [0, 520, 390, 56], a, [0, 820, 402, 54])
    else:
        P("D-text-rows", st, b, [0, 676, 200, 84], a, [0, 125, 200, 100])
        P("D-text-bottom-gap", st, b, [0, 730, 390, 36], a, [0, 759, 402, 36])
        P("D-keyrow-start" if "fit" in st else "D-keyrow-end-scrolled", st, b, [0, 756, 390, 88], a, [0, 785, 402, 89])
P("D-keyrow-end", "kbup", "b_kbo_keysend_tile", [0, 98, 195, 56], "a_fit_kbup_keysend", [207, 820, 195, 54])
P("D-keyrow-end", "kbhidden", "b_kbc_fit_keysend", [195, 756, 195, 88], "a_wide_kbhidden", [207, 785, 195, 89])
P("D-kbkey-icon", "kbup", "b_kbo_keysend_tile", [139, 106, 52, 40], "a_fit_kbup_keysend", [346, 829, 52, 40])
P("D-kbkey-icon", "kbhidden", "b_kbc_fit_keysend", [334, 764, 52, 40], "a_wide_kbhidden", [346, 794, 52, 40])
P("E-full", "browse", "b_signin", [0, 0, 390, 844], "a_signin", [0, 0, 402, 874])
P("E-sheet-corner-close", "browse", "b_signin", [0, 50, 70, 60], "a_signin", [0, 58, 70, 60])
P("E-address-pill", "browse", "b_signin", [54, 64, 282, 46], "a_signin", [54, 72, 294, 46])
P("E-reload", "browse", "b_signin", [334, 64, 56, 46], "a_signin", [346, 72, 56, 46])
P("E-web-top-edge", "browse", "b_signin", [0, 104, 390, 30], "a_signin", [0, 112, 402, 30])
P("E-bottom-bar", "browse", "b_signin", [0, 744, 390, 100], "a_signin", [0, 774, 402, 100])
P("E-back-forward", "browse", "b_signin", [6, 762, 104, 52], "a_signin", [6, 792, 104, 52])
P("E-done", "browse", "b_signin", [110, 758, 274, 60], "a_signin", [110, 788, 286, 60])
json.dump({"sources": sources, "pairs": pairs}, open(os.path.join(E, "pairs.json"), "w"), indent=1)
print(len(pairs), "pairs")
