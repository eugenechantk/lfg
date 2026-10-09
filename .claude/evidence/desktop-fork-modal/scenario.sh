#!/bin/zsh
# Usage: scenario.sh <name> <mode ok|fail> <hide 0|1>
S=${0:A:h}; AX=~/.claude/skills/macos-test/axdriver/bin/axdriver; PID=$(cat $S/app.pid)
ROW=$($AX find --app $PID --role AXButton | python3 -c "import json,sys; print([i for i,m in enumerate(json.load(sys.stdin)) if 'AXOutline' in m.get('path','')][0])")
name=$1; echo $2 > $S/mode; hide=$3
sheet() { $AX find --app $PID --role AXSheet | python3 -c "import json,sys; print('sheet=yes' if json.load(sys.stdin) else 'sheet=no')"; }
texts() { $AX find --app $PID --role AXStaticText | python3 -c "import json,sys; print([m.get('value') for m in json.load(sys.stdin) if 'Sheet' in m.get('path','')])"; }
$AX press --app $PID --role AXButton --index $ROW --action AXShowMenu >/dev/null 2>&1; sleep 1
$AX press --app $PID --role AXMenuItem --identifier fork_session >/dev/null; sleep 1.5
echo "[$name +1.5s] $(sheet) $(texts)"; $AX screenshot --app $PID --out $S/$name-1-during.png >/dev/null
if [[ $hide == 1 ]]; then
  $AX press --app $PID --identifier fork_progress_close >/dev/null; sleep 0.8
  echo "[$name after Hide] $(sheet)"
  $AX press --app $PID --role AXButton --index $ROW --action AXShowMenu >/dev/null 2>&1; sleep 1
  echo "[$name menu while hidden] $($AX find --app $PID --identifier fork_session | python3 -c "import json,sys; m=json.load(sys.stdin); print([(x.get('title'), x.get('enabled')) for x in m])")"
  $AX type --app $PID --key escape >/dev/null; sleep 0.5
fi
sleep 9
echo "[$name +11s] $(sheet) $(texts)"; $AX screenshot --app $PID --out $S/$name-2-after.png >/dev/null
$AX find --app $PID --role AXSheet --index 0 >/dev/null
