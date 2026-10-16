"""Write pairs.json for prepare_evidence.py. Rects come from the board DOM dumps and the pixel scans
(scan-*.txt, element-compare-*.tsv); both images share one coordinate system (1 px = 1 pt, top-aligned)."""
import json, os

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
states = {
    "expanded": ("board-expanded-480x1032.png", "app-expanded-srgb.png"),
    "collapse-working": ("board-collapse-working-480x1032.png", "app-collapse-working-srgb.png"),
    "collapse-needsInput": ("board-collapse-needsInput-480x1032.png", "app-collapse-needsInput-srgb.png"),
    "collapse-recent": ("board-collapse-recent-480x1032.png", "app-collapse-recent-srgb.png"),
    "collapse-all": ("board-collapse-all-480x1032.png", "app-collapse-all-srgb.png"),
}
sources = {}
for s, (b, a) in states.items():
    sources[f"design-{s}"] = {"path": b, "pixels_per_unit": 1, "viewport": [480, 1032]}
    sources[f"app-{s}"] = {"path": a, "pixels_per_unit": 1, "viewport": [400, 912]}

comps = {
    "expanded": [
        ("01-window-controls", [0, 0, 90, 52]),
        ("02-switcher", [112, 4, 200, 44]),
        ("03-search-button", [350, 4, 46, 44]),
        ("04-titlebar-hoststrip-edge", [0, 36, 400, 50]),
        ("05-host-strip-left", [0, 52, 220, 30]),
        ("06-by-status-pill", [298, 48, 96, 30]),
        ("07-header-needs-input", [0, 82, 400, 39]),
        ("08-row-needs-question", [0, 120, 400, 76]),
        ("09-row-needs-permission", [0, 195, 400, 76]),
        ("10-header-working", [0, 270, 400, 39]),
        ("11-row-working-1", [0, 308, 400, 76]),
        ("12-row-working-task", [0, 383, 400, 76]),
        ("13-row-working-3", [0, 458, 400, 76]),
        ("14-header-recent", [0, 533, 400, 39]),
        ("15-row-recent-closed-1", [0, 571, 400, 76]),
        ("16-row-recent-closed-2", [0, 646, 400, 76]),
        ("17-row-offline-dimmed", [0, 722, 400, 76]),
        ("18-time-column", [0, 120, 62, 680]),
        ("19-window-top-860", [0, 0, 400, 860]),
    ],
    "collapse-working": [
        ("20-header-working-collapsed", [0, 270, 400, 39]),
        ("21-collapse-working-context", [0, 195, 400, 240]),
        ("22-window-collapse-working", [0, 0, 400, 860]),
    ],
    "collapse-needsInput": [
        ("23-header-needs-collapsed", [0, 82, 400, 39]),
        ("24-collapse-needs-context", [0, 82, 400, 160]),
        ("25-window-collapse-needs", [0, 0, 400, 860]),
    ],
    "collapse-recent": [
        ("26-header-recent-collapsed", [0, 533, 400, 39]),
        ("27-collapse-recent-context", [0, 458, 400, 160]),
        ("28-window-collapse-recent", [0, 0, 400, 860]),
    ],
    "collapse-all": [
        ("29-headers-all-collapsed", [0, 82, 400, 112]),
        ("30-window-collapse-all", [0, 0, 400, 860]),
    ],
}
pairs = []
for s, lst in comps.items():
    for cid, rect in lst:
        pairs.append({"id": cid, "state": s,
                      "design": {"source": f"design-{s}", "rect": rect},
                      "app": {"source": f"app-{s}", "rect": rect}})
json.dump({"sources": sources, "pairs": pairs}, open(os.path.join(HERE, "pairs.json"), "w"), indent=1)
print(len(pairs), "pairs")
