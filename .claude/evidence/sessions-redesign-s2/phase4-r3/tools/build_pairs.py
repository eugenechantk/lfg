"""Build pairs.json for prepare_evidence.py from the board DOM dumps.

Rects: board DOM frame rounded outward, padded 2px. The app rect uses the same frame shifted by the app offset measured
for that component (title-ink dy from measure-text-<state>.tsv for rows, header-label dy for headers; 0 for chrome,
whose measured edge deltas are all <=1.1px). All measured app offsets are <=2px, so the padded rect contains the app copy.
"""
import json
import os
import sys

root = sys.argv[1]
os.chdir(root)
sys.path.insert(0, os.path.join(root, "tools"))
from measure_boxes import records  # noqa: E402

STATES = ["open", "fold-needs", "fold-working", "fold-recent", "fold-all"]
sources = {}
pairs = []
for st in STATES:
    sources[f"board-{st}"] = {"path": f"../board-{st}.png", "pixels_per_unit": 1, "viewport": [400, 860]}
    sources[f"app-{st}"] = {"path": f"../app-{st}-srgb.png", "pixels_per_unit": 1, "viewport": [400, 912]}
    # measured text offsets
    dy_of = {}
    for line in open(f"measure-text-{st}.tsv").read().splitlines()[1:]:
        f = line.split("\t")
        if len(f) > 6:
            dy_of.setdefault(f[1], []).append(int(f[5]))
    chrome = [
        ("title-bar", [0, 0, 400, 52]),
        ("native-window-controls (exception)", [0, 8, 80, 36]),
        ("segmented-control", [118, 7, 188, 38]),
        ("search-button", [354, 7, 38, 38]),
        ("host-strip", [0, 50, 400, 32]),
        ("by-status-pill", [302, 49, 86, 28]),
        ("list-top-border", [0, 76, 400, 12]),
    ]
    for cid, r in chrome:
        pairs.append({"id": cid, "state": st,
                      "design": {"source": f"board-{st}", "rect": r},
                      "app": {"source": f"app-{st}", "rect": r}})
    recs = records(f"board-dom-{st}.tsv")
    texts = [f for f in recs if f[0] == "text"]
    n_row = 0
    for f in recs:
        if f[0] != "box":
            continue
        lab = f[1]
        x, y, w, h = map(float, f[2:6])
        if lab.startswith("button[expanded"):
            name = lab.split("] ", 1)[1].split(" ")[0]
            kind = "header-" + name.lower()
            first = [t for t in texts if abs(float(t[3]) - y) < 20][0][1]
        elif lab.startswith("a ") and w == 400:
            n_row += 1
            # row title = first 14px/600 text inside the row frame
            ts = [t for t in texts if float(t[3]) >= y and float(t[3]) < y + h and t[6] == "14px" and t[7] == "600"]
            first = ts[0][1] if ts else ""
            kind = f"row-{n_row:02d} {first[:28]}"
        else:
            continue
        dy = 0
        if first in dy_of:
            vals = dy_of[first]
            dy = round(sum(vals) / len(vals))
        x0, y0 = int(x) - 2, int(y) - 2
        rh = int(h + 0.999) + 4
        pairs.append({"id": kind, "state": st,
                      "design": {"source": f"board-{st}", "rect": [max(0, x0), max(0, y0), 400 - max(0, x0), rh]},
                      "app": {"source": f"app-{st}", "rect": [max(0, x0), max(0, y0 + dy), 400 - max(0, x0), rh]}})
import re
for p in pairs:
    p["id"] = re.sub(r"[^a-z0-9]+", "-", (p["state"] + "--" + p["id"]).lower()).strip("-")
os.makedirs("crops-manifest", exist_ok=True)
json.dump({"sources": sources, "pairs": pairs}, open("crops-manifest/pairs.json", "w"), indent=1)
print(len(pairs), "pairs")
