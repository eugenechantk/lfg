#!/bin/sh
# Capture this worktree's desktop build on screen, active and then inactive.
S=/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad
sh "$S/gui_start.sh"
PID=$(cat "$S/desk-gui.pid")
sleep 4
rect() {
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID)
    set p to position of window 1
    set s to size of window 1
    return ((item 1 of p) as text) & \",\" & ((item 2 of p) as text) & \",\" & ((item 1 of s) as text) & \",\" & ((item 2 of s) as text)
  end tell"
}
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set frontmost to true" >/dev/null
sleep 1
R=$(rect); screencapture -x -R"$R" "$S/snaps/win-active.png" && echo "active $R"
osascript -e 'tell application "Finder" to activate' >/dev/null
sleep 1.5
R=$(rect); screencapture -x -R"$R" "$S/snaps/win-inactive.png" && echo "inactive $R"
kill $PID
echo "quit $PID"
python3 - "$S" <<'EOF'
import sys
from PIL import Image
s = sys.argv[1]
for n in ("win-active", "win-inactive"):
    im = Image.open(f"{s}/snaps/{n}.png").convert("RGB")
    print(n, [im.getpixel((150, y)) for y in range(46, 57)])
EOF
