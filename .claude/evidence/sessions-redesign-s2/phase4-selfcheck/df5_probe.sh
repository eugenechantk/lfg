#!/bin/sh
# DF5 live probe: refresh with the stub Air up, stop it, refresh again, shoot.
S=/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad
APP=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/desktop/build/lfg.app/Contents/MacOS/lfg
rm -f "$S/stub.log" "$S/df5.out"
"$HOME/.bun/bin/bun" "$S/stub-air.ts" > "$S/stub.log" 2>&1 &
STUB=$!
sleep 1.5
LFG_DESKTOP_CONFIG_DIR="$S/desk-live" "$APP" --window-shot 400 "$S/snaps/live3.png" --height 860 --live --refresh-twice 10 > "$S/df5.out" 2>&1 &
SHOT=$!
i=0
until grep -q "resumable" "$S/stub.log" || [ $i -ge 60 ]; do sleep 0.5; i=$((i+1)); done
echo "first refresh reached the stub after ~$((i/2))s; stopping it"
kill $STUB
wait $STUB 2>/dev/null
echo "8797 listeners after kill: $(lsof -nP -iTCP:8797 -sTCP:LISTEN -t | wc -l)"
wait $SHOT
echo "--- probe output"
cat "$S/df5.out"
echo "--- stub log"
cat "$S/stub.log"
