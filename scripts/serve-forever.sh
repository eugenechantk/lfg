#!/usr/bin/env bash
#
# Auto-restarting lfg server.
#
# Bun's HTTP/SSE server has occasionally segfaulted under long-lived SSE
# connections (a Bun runtime bug, not lfg's code). The Bun version is pinned in
# `.bun-version`; this wrapper additionally keeps the server alive by restarting
# it on any non-clean exit, with exponential backoff so a fast-crashing build
# can't hot-loop.
#
# Usage:  bun run serve:forever   (or)   bash scripts/serve-forever.sh
# Stop:   Ctrl-C  (forwards the signal and exits cleanly)
#
set -uo pipefail
cd "$(dirname "$0")/.."

# lfg listens on loopback (LFG_HOST default 127.0.0.1) — expose it on the tailnet
# with `tailscale serve --bg 127.0.0.1:8766` (tailnet-only HTTPS at the machine's
# MagicDNS URL), NOT funnel (which is public). Point the iOS client at that URL.
# For direct raw-IP access instead, export LFG_HOST=0.0.0.0 before launch.

PIN="$(tr -d '[:space:]' < .bun-version 2>/dev/null || true)"
CUR="$(bun --version 2>/dev/null || echo unknown)"
if [ -n "$PIN" ] && [ "$PIN" != "$CUR" ]; then
  echo "[serve-forever] WARNING: running bun $CUR but .bun-version pins $PIN." >&2
  echo "[serve-forever]          pin it with:  bun upgrade --to $PIN" >&2
fi

running=1
child=""
shutdown() { running=0; [ -n "$child" ] && kill "$child" 2>/dev/null; }
trap shutdown INT TERM

backoff=1
while [ "$running" -eq 1 ]; do
  start=$(date +%s)
  echo "[serve-forever] starting lfg serve (bun $CUR) — $(date)"
  bun run src/cli.ts serve &
  child=$!
  wait "$child"
  code=$?
  child=""
  [ "$running" -eq 0 ] && break

  uptime=$(( $(date +%s) - start ))
  echo "[serve-forever] lfg serve exited (code $code) after ${uptime}s"

  # Healthy run resets the backoff; a fast crash backs off (cap 30s).
  if [ "$uptime" -ge 30 ]; then
    backoff=1
  else
    backoff=$(( backoff * 2 )); [ "$backoff" -gt 30 ] && backoff=30
  fi
  echo "[serve-forever] restarting in ${backoff}s…"
  sleep "$backoff"
done

echo "[serve-forever] stopped."
