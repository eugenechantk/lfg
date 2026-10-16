#!/bin/sh
# Run measure.py on a query file in measure/q/. usage: m.sh <query-basename>
E=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r13
uv run --quiet --script "$E/measure/measure.py" "$E" "$E/measure/q/$1.txt" | tee "$E/measure/q/$1.out"
