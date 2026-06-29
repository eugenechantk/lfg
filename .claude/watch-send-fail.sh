#!/usr/bin/env bash
# Watch all claude session queues for a send that goes pending/sending/failed,
# and on the first hit dump the queue error + a snapshot of that session's tmux
# pane. Non-intrusive: read-only polling of the live server + capture-pane.
set -u
BASE=http://localhost:8766
OUT=/Users/eugenechan/dev/personal/lfg/.claude/send-fail-capture.txt
: > "$OUT"
echo "watching… reproduce a failing send now" >&2

# sessionId -> tmuxTarget map (once)
MAP=$(curl -s --max-time 25 "$BASE/api/sessions" | python3 -c "import sys,json
d=json.load(sys.stdin)
for s in d.get('sessions',d):
 if s.get('agent')=='claude' and s.get('sessionId') and s.get('tmuxTarget'):
  print(s['sessionId'], s['tmuxTarget'])")

IDS=$(echo "$MAP" | awk '{print $1}')

for n in $(seq 1 600); do   # ~5 min at 0.5s
  for id in $IDS; do
    q=$(curl -s --max-time 2 "$BASE/api/sessions/$id/queue")
    hit=$(echo "$q" | python3 -c "import sys,json
try:
 d=json.load(sys.stdin)
 for m in d.get('queue',[]):
  if m.get('status') in ('failed','pending','sending'):
   print(m['status']+'|'+str(m.get('attempts'))+'|'+(m.get('error') or '')+'|'+(m.get('text') or '')[:80]); break
except: pass")
    if [ -n "$hit" ]; then
      tgt=$(echo "$MAP" | awk -v i="$id" '$1==i{print $2}')
      {
        echo "=== HIT $(date '+%H:%M:%S') ==="
        echo "session: $id"
        echo "target:  $tgt"
        echo "queue:   $hit"
        echo "--- capture-pane tail ---"
        tmux capture-pane -t "$tgt" -p 2>/dev/null | tail -20
        echo "=== END ==="
      } >> "$OUT"
      echo "CAPTURED -> $OUT" >&2
      # keep watching this one a couple more samples to see if it stays failed
    fi
  done
  sleep 0.5
done
echo "watch window ended" >&2
