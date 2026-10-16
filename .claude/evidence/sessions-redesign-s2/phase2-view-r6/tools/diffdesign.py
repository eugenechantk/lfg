# /// script
# dependencies = ["pillow"]
# ///
"""Pixel-diff this round's board renders against round 5's (baseline-identity check)."""
import sys
from PIL import Image, ImageChops

D = "/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/"
for n in ["b4-queued", "b5-failed"]:
    a = Image.open(D + "phase2-view-r6/design/" + n + ".png").convert("RGB")
    b = Image.open(D + "phase2-view-r5/design/" + n + ".png").convert("RGB")
    diff = ImageChops.difference(a, b)
    bbox = diff.getbbox()
    mx = max(diff.getextrema(), key=lambda e: e[1])[1] if bbox else 0
    print(n, a.size, "diff bbox:", bbox, "max channel diff:", mx)
for extra in sys.argv[1:]:
    a = Image.open(extra).convert("RGB")
    b = Image.open(D + "phase2-view-r6/design/b4-queued.png").convert("RGB")
    print(extra.split("/")[-1], "vs r6 b4:", ImageChops.difference(a, b).getbbox())
