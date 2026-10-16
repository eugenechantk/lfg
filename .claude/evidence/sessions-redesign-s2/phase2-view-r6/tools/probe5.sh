#!/bin/sh
# Batch 5: header/status, transcript rhythm, strip content, composer. Boards at 1x, app at 3x.
R=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r6
m() { uv run --script "$R/tools/m.py" "$@" 2>&1 | grep -v Installed; }
echo "== HEADER rows (title+status) board4 x 80..310 y 55..110"; m rows "$R/design/b4-queued.png" 1 80 310 55 110 000000 40
echo "== HEADER rows app q0 x 80..322 y 60..115"; m rows "$R/app/q0.png" 3 80 322 60 115 000000 40
echo "== back button rows app q0 x 12..62 (button)"; m rows "$R/app/q0.png" 3 12 62 40 110 000000 12
echo "== status cols board4 y 86..101"; m cols "$R/design/b4-queued.png" 1 80 310 86 101 000000 40
echo "== status cols app q0 y 90..103"; m cols "$R/app/q0.png" 3 80 322 89 103 000000 40
echo "== status cols board5 y 86..101"; m cols "$R/design/b5-failed.png" 1 80 310 86 101 000000 40
echo "== status cols app f0 y 89..103"; m cols "$R/app/f0.png" 3 80 322 89 103 000000 40
echo "== HEADER rows board5"; m rows "$R/design/b5-failed.png" 1 80 310 55 110 000000 40
echo "== HEADER rows app f0"; m rows "$R/app/f0.png" 3 80 322 60 115 000000 40
echo "== TRANSCRIPT rows board4 x 16..120 y 500..682"; m rows "$R/design/b4-queued.png" 1 16 120 500 682 000000 40
echo "== TRANSCRIPT rows app q0 x 16..120 y 500..713"; m rows "$R/app/q0.png" 3 16 120 500 713 000000 40
echo "== TRANSCRIPT rows board5 x 16..374 y 520..682"; m rows "$R/design/b5-failed.png" 1 16 374 520 682 000000 40
echo "== TRANSCRIPT rows app f0 x 16..386 y 540..713"; m rows "$R/app/f0.png" 3 16 386 540 713 000000 40
echo "== bubble cols board5 y 545..570"; m cols "$R/design/b5-failed.png" 1 0 390 545 570 000000 60
echo "== bubble cols app f0 y 576..601"; m cols "$R/app/f0.png" 3 0 402 576 601 000000 60
echo "== STRIP content cols q0 y 715..743 vs 18181A"; m cols "$R/app/q0.png" 3 14 388 716 742 18181A 40
echo "== STRIP content rows q0 x 40..340"; m rows "$R/app/q0.png" 3 40 340 714 744 18181A 40
echo "== STRIP content cols f0 y 715..743"; m cols "$R/app/f0.png" 3 14 388 716 742 18181A 40
echo "== STRIP content rows f0 x 40..340"; m rows "$R/app/f0.png" 3 40 340 714 744 18181A 40
echo "== COMPOSER rows q0 x 20..380 y 751..846 vs 1A1A1C"; m rows "$R/app/q0.png" 3 20 380 753 844 1A1A1C 40
echo "== COMPOSER rows b4 x 20..370 y 721..815 vs 1C1C1E"; m rows "$R/design/b4-queued.png" 1 20 370 722 815 1C1C1E 40
echo "== COMPOSER cols q0 y 790..810"; m cols "$R/app/q0.png" 3 14 388 790 812 1A1A1C 40
echo "== COMPOSER cols b4 y 776..800"; m cols "$R/design/b4-queued.png" 1 14 376 776 800 1C1C1E 40
echo "== COMPOSER rows f0"; m rows "$R/app/f0.png" 3 20 380 753 844 1A1A1C 40
echo "== COMPOSER rows b5"; m rows "$R/design/b5-failed.png" 1 20 370 722 815 1C1C1E 40
echo "== COMPOSER cols f0 y 790..812"; m cols "$R/app/f0.png" 3 14 388 790 812 1A1A1C 40
echo "== COMPOSER cols b5 y 776..800"; m cols "$R/design/b5-failed.png" 1 14 376 776 800 1C1C1E 40
