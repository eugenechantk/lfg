#!/bin/sh
# Usage: stream-probe.sh <seconds> <outdir>
# Opens two /api/events streams in parallel on 127.0.0.1:8766:
#   A) since=999999999 (unservable cursor -> expect resync then id: rows)
#   B) since=<current head> (control: servable cursor -> expect no resync, id: rows)
SECS=${1:-40}; OUT=${2:-.}
mkdir -p "$OUT"
HEAD0=$(curl -sS http://127.0.0.1:8766/api/ping | sed -E 's/.*"seq":([0-9]+).*/\1/')
echo "host=$(hostname) start=$(date '+%Y-%m-%d %H:%M:%S %z') ping.seq=$HEAD0 secs=$SECS" > "$OUT/meta.txt"
curl -sN -m "$SECS" "http://127.0.0.1:8766/api/events?since=999999999" > "$OUT/resync.raw" 2>"$OUT/resync.err" &
A=$!
curl -sN -m "$SECS" "http://127.0.0.1:8766/api/events?since=$HEAD0" > "$OUT/control.raw" 2>"$OUT/control.err" &
B=$!
wait $A; echo "resync curl exit=$?" >> "$OUT/meta.txt"
wait $B; echo "control curl exit=$?" >> "$OUT/meta.txt"
HEAD1=$(curl -sS http://127.0.0.1:8766/api/ping | sed -E 's/.*"seq":([0-9]+).*/\1/')
echo "end=$(date '+%Y-%m-%d %H:%M:%S %z') ping.seq=$HEAD1" >> "$OUT/meta.txt"
for f in resync control; do
  echo "--- $f summary"
  echo "resync frames: $(grep -c '^event: resync' "$OUT/$f.raw")"
  echo "first frame: $(head -2 "$OUT/$f.raw" | tr '\n' ' ')"
  echo "hb lines: $(grep '^: hb' "$OUT/$f.raw" | tr '\n' ' ')"
  echo "first hb: $(grep '^: hb' "$OUT/$f.raw" | head -1)  last hb: $(grep '^: hb' "$OUT/$f.raw" | tail -1)"
  echo "id rows: $(grep -c '^id: ' "$OUT/$f.raw")  ids: $(grep '^id: ' "$OUT/$f.raw" | sed 's/id: //' | tr '\n' ' ')"
  echo "event types: $(grep '^event: ' "$OUT/$f.raw" | sort | uniq -c | tr '\n' ' ')"
done >> "$OUT/meta.txt"
cat "$OUT/meta.txt"
