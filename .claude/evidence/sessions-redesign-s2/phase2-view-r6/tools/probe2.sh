#!/bin/sh
# Batch 2: the strip's ellipsis glyph, board 3x renders vs app native 3x (closed and open strip).
R=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r6
g() { uv run --script "$R/tools/dotsglyph.py" "$@" 2>&1 | grep -v Installed; }
echo "== board4 3x dots (open bg)"; g "$R/design/glyphs3x-b4.png" 3 4,4,68,68
echo "== board4 3x dots (closed bg)"; g "$R/design/glyphs3x-b4.png" 3 76,4,140,68
echo "== board5 3x dots (open bg)"; g "$R/design/glyphs3x-b5.png" 3 4,4,68,68
echo "== board4 1x dots in artboard (open)"; g "$R/design/b4-queued.png" 1 348,686,372,710
echo "== app q0 dots (closed)"; g "$R/app/q0.png" 3 1080,2154,1150,2220
echo "== app q1 dots (open)"; g "$R/app/q1.png" 3 1080,2154,1150,2220
echo "== app f0 dots (closed)"; g "$R/app/f0.png" 3 1080,2154,1150,2220
echo "== app f1 dots (open)"; g "$R/app/f1.png" 3 1080,2154,1150,2220
