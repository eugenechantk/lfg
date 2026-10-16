#!/bin/sh
# Batch 1: strip, menu and composer geometry on the app frames (pt, scale 3) and the boards (scale 1).
R=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r6
m() { uv run --script "$R/tools/m.py" "$@" 2>&1 | grep -v Installed; }
echo "== q0 strip edges at y=729 (thr 4)"; m hline "$R/app/q0.png" 3 735 0 402 4
echo "== q1 strip edges at y=740 (thr 4)"; m hline "$R/app/q1.png" 3 740 0 402 4
echo "== q1 menu: vertical through x=380 (right of icons)"; m vline "$R/app/q1.png" 3 380 640 760 4
echo "== q1 menu: vertical through x=300 (text-free area?)"; m vline "$R/app/q1.png" 3 300 640 760 4
echo "== q1 menu: horizontal at y=700 (Remove row)"; m hline "$R/app/q1.png" 3 700 100 402 4
echo "== f1 menu: vertical x=380"; m vline "$R/app/f1.png" 3 380 640 760 4
echo "== f1 menu: horizontal at y=700"; m hline "$R/app/f1.png" 3 700 100 402 4
echo "== board4 menu vertical x=370"; m vline "$R/design/b4-queued.png" 1 370 520 720 4
echo "== board4 menu vertical x=300"; m vline "$R/design/b4-queued.png" 1 300 520 720 4
echo "== board5 menu vertical x=370"; m vline "$R/design/b5-failed.png" 1 370 520 720 4
