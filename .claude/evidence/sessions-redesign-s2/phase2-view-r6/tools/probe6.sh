#!/bin/sh
# Batch 6: composer bottom row (corrected band +31), board 5 bubble/prose rhythm left of the menu, bubble right edge.
R=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r6
m() { uv run --script "$R/tools/m.py" "$@" 2>&1 | grep -v Installed; }
echo "== COMPOSER cols q0 y 807..831"; m cols "$R/app/q0.png" 3 14 388 807 831 1A1A1C 40
echo "== COMPOSER cols f0 y 807..831"; m cols "$R/app/f0.png" 3 14 388 807 831 1A1A1C 40
echo "== chip box cols q0 (chip bg vs composer) y 818"; m hline "$R/app/q0.png" 3 818 40 200 4
echo "== chip box rows q0 x 60..62"; m vline "$R/app/q0.png" 3 62 795 845 4
echo "== chip box cols b4 y 788"; m hline "$R/design/b4-queued.png" 1 776 40 200 4
echo "== stop/send rows q0 x 361"; m vline "$R/app/q0.png" 3 361 795 845 6
echo "== send rows f0 x 361"; m vline "$R/app/f0.png" 3 361 795 845 6
echo "== send rows b5 x 350"; m vline "$R/design/b5-failed.png" 1 350 765 815 6
echo "== board5 transcript rows x 16..140"; m rows "$R/design/b5-failed.png" 1 16 140 530 682 000000 40
echo "== app f0 transcript rows x 16..150"; m rows "$R/app/f0.png" 3 16 150 560 713 000000 40
echo "== bubble right edge f0 at y 591"; m hline "$R/app/f0.png" 3 591 360 402 6
echo "== bubble right edge b5 at y 558"; m hline "$R/design/b5-failed.png" 1 558 350 390 6
echo "== bubble left edge f0 at y 591"; m hline "$R/app/f0.png" 3 591 90 120 6
echo "== q1 bubble/prose check: card left region colour at x 150 y 600"; uv run --script "$R/tools/samp.py" "$R/app/f1.png@3" 341,590 341,600 300,600 "$R/design/b5-failed.png@1" 330,560 330,570 300,570 2>&1 | grep -v Installed
