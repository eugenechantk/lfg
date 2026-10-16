#!/bin/sh
# Batch 3: glyph sheets (board SVG at 3x vs app native 3x) and enlarged pairs for the strip and menu.
R=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r6
gs() { uv run --script "$R/tools/glyphsheet.py" "$@" 2>&1 | grep -v Installed; }
zp() { uv run --script "$R/tools/zoompair.py" "$@" 2>&1 | grep -v Installed; }
gs "$R/crops/glyphs3x-b4-vs-q0q1.png" "$R/design/glyphs3x-b4.png" "$R/app/q1.png" dots-open:360,719,384,743 spinner:19,717,43,741 arrowup:353,579,377,603 pencil:353,629,377,653 trash:353,672,377,696
gs "$R/crops/glyphs3x-b4-vs-q0closed.png" "$R/design/glyphs3x-b4.png" "$R/app/q0.png" dots-closed:360,719,384,743 spinner:19,717,43,741
gs "$R/crops/glyphs3x-b5-vs-f1.png" "$R/design/glyphs3x-b5.png" "$R/app/f1.png" dots-open:360,719,384,743 error:19,717,43,741 retry:353,586,377,610 pencil:353,629,377,653 trash:353,672,377,696
gs "$R/crops/glyphs3x-b5-vs-f0closed.png" "$R/design/glyphs3x-b5.png" "$R/app/f0.png" dots-closed:360,719,384,743 error:19,717,43,741
# enlarged strip + menu region, board (1x) vs app (3x), both at 4 px/pt; board rect offset +11 x, +31 y for the app
zp "$R/crops/zoom-menu-strip-b4-vs-q1.png" "$R/design/b4-queued.png" 1 100,520,390,720 "$R/app/q1.png" 3 111,551,401,751 4
zp "$R/crops/zoom-menu-strip-b5-vs-f1.png" "$R/design/b5-failed.png" 1 100,520,390,720 "$R/app/f1.png" 3 111,551,401,751 4
zp "$R/crops/zoom-strip-closed-b4-vs-q0.png" "$R/design/b4-queued.png" 1 0,676,390,720 "$R/app/q0.png" 3 0,707,402,751 4
