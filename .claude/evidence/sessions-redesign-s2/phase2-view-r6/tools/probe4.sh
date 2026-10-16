#!/bin/sh
# Batch 4: menu card geometry. Board columns at x=330 (no text) and rows at mid-row; app at +11 x.
R=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r6
m() { uv run --script "$R/tools/m.py" "$@" 2>&1 | grep -v Installed; }
echo "== q1 vline x=341 (card top/bottom, dividers)"; m vline "$R/app/q1.png" 3 341 540 720 6
echo "== q1 hline y=641 (Edit row: card L/R, text, icon)"; m hline "$R/app/q1.png" 3 641 100 402 6
echo "== q1 rows: ink in card text column x 150..330, y 560..710 vs bg 29292C"; m rows "$R/app/q1.png" 3 150 330 560 712 29292C 30
echo "== q1 cols: icon column x 340..390 y 575..700"; m cols "$R/app/q1.png" 3 340 390 575 700 29292C 30
echo "== q1 rows icon column"; m rows "$R/app/q1.png" 3 355 380 570 705 29292C 30
echo "== b4 rows: card text column x 140..330 y 530..675 vs bg 2B2B2C"; m rows "$R/design/b4-queued.png" 1 140 330 530 675 2B2B2C 30
echo "== b4 cols icon column"; m cols "$R/design/b4-queued.png" 1 335 378 545 670 2B2B2C 30
echo "== b4 rows icon column"; m rows "$R/design/b4-queued.png" 1 340 370 540 672 2B2B2C 30
echo "== b4 hline y=610 (Edit row)"; m hline "$R/design/b4-queued.png" 1 610 100 390 6
echo "== f1 vline x=341"; m vline "$R/app/f1.png" 3 341 560 720 6
echo "== f1 hline y=641"; m hline "$R/app/f1.png" 3 641 100 402 6
echo "== f1 rows text column x 170..330 y 570..710"; m rows "$R/app/f1.png" 3 170 330 572 712 29292C 30
echo "== f1 rows icon column"; m rows "$R/app/f1.png" 3 355 380 580 705 29292C 30
echo "== b5 vline x=330"; m vline "$R/design/b5-failed.png" 1 330 530 690 6
echo "== b5 rows text column x 160..330 y 548..675"; m rows "$R/design/b5-failed.png" 1 160 330 548 675 2B2B2C 30
echo "== b5 rows icon column"; m rows "$R/design/b5-failed.png" 1 340 370 552 672 2B2B2C 30
echo "== b5 hline y=610"; m hline "$R/design/b5-failed.png" 1 610 100 390 6
