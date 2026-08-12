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
# It ALSO enforces a memory ceiling. On 2026-08-07 this process leaked to 31 GB
# on a 36 GB machine and held the whole system in jetsam thrash for four hours
# (24 JetsamEvent reports between 02:35 and 06:09) until the Mac had to be
# power-cycled. Crash-restart alone does not cover that: a process that leaks
# instead of crashing gets unbounded runway, and the blast radius is the machine
# rather than this one service. The ceiling converts that failure mode into a
# routine restart.
#
# Usage:  bun run serve:forever   (or)   bash scripts/serve-forever.sh
# Stop:   Ctrl-C  (forwards the signal and exits cleanly)
#
# Tunables:
#   LFG_MAX_RSS_MB     hard ceiling; child is restarted above it   (default 4096)
#   LFG_RSS_WARN_PCT   log a warning at this % of the ceiling      (default 75)
#   LFG_RSS_CHECK_SECS how often to sample the child's RSS         (default 30)
#
set -uo pipefail
cd "$(dirname "$0")/.."

# lfg listens on loopback (LFG_HOST default 127.0.0.1) — expose it on the tailnet
# with `tailscale serve --bg 127.0.0.1:8766` (tailnet-only HTTPS at the machine's
# MagicDNS URL), NOT funnel (which is public). Point the iOS client at that URL.
# For direct raw-IP access instead, export LFG_HOST=0.0.0.0 before launch.

MAX_RSS_MB="${LFG_MAX_RSS_MB:-4096}"
WARN_PCT="${LFG_RSS_WARN_PCT:-75}"
CHECK_SECS="${LFG_RSS_CHECK_SECS:-30}"
WARN_RSS_MB=$(( MAX_RSS_MB * WARN_PCT / 100 ))

PIN="$(tr -d '[:space:]' < .bun-version 2>/dev/null || true)"

# Resolve the pinned Bun explicitly rather than trusting PATH.
#
# This wrapper is normally started by the lfg desktop app (a login item), whose
# PATH is launchd's — it has /opt/homebrew/bin but NOT ~/.bun/bin. An
# interactive shell has ~/.bun/bin first. On 2026-08-07 that meant a hand-run
# server got the pinned bun 1.3.14 while the always-on autostarted one silently
# got Homebrew's bun 1.2.15 (June 2025), and only the autostarted one leaked.
# A warning printed into a log nobody tails did not prevent that, so pick the
# right binary here instead of merely complaining about the wrong one.
BUN="bun"
if [ -n "$PIN" ]; then
  for cand in "${BUN_INSTALL:-$HOME/.bun}/bin/bun" "$HOME/.bun/bin/bun" \
              "$(command -v bun 2>/dev/null || true)" /opt/homebrew/bin/bun /usr/local/bin/bun; do
    [ -n "$cand" ] && [ -x "$cand" ] || continue
    if [ "$("$cand" --version 2>/dev/null || true)" = "$PIN" ]; then
      BUN="$cand"
      break
    fi
  done
fi

CUR="$("$BUN" --version 2>/dev/null || echo unknown)"
if [ -n "$PIN" ] && [ "$PIN" != "$CUR" ]; then
  echo "[serve-forever] WARNING: no bun matching the pinned $PIN found; using $BUN ($CUR)." >&2
  echo "[serve-forever]          install it with:  bun upgrade --to $PIN" >&2
else
  echo "[serve-forever] bun $CUR ($BUN)"
fi

running=1
child=""
shutdown() { running=0; [ -n "$child" ] && kill "$child" 2>/dev/null; }
trap shutdown INT TERM

# Sample the child's RSS in MB. Empty output means it is gone.
rss_mb_of() {
  local kb
  kb="$(ps -o rss= -p "$1" 2>/dev/null | tr -d ' ')"
  [ -n "$kb" ] && echo $(( kb / 1024 ))
}

# TERM, then KILL after a grace period, so an over-ceiling child always dies.
terminate() {
  local pid="$1" i
  kill "$pid" 2>/dev/null
  for i in $(seq 1 10); do
    kill -0 "$pid" 2>/dev/null || return
    sleep 1
  done
  echo "[serve-forever] child $pid ignored SIGTERM — sending SIGKILL" >&2
  kill -9 "$pid" 2>/dev/null
}

# Watch the child until it exits or crosses the ceiling. Ticks at 5s (not
# CHECK_SECS) so Ctrl-C stays responsive — bash only runs a trap once the
# current foreground command returns, and a 30s sleep would stall shutdown.
supervise() {
  local pid="$1" elapsed=0 mb warned=0
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    [ "$running" -eq 0 ] && return 0
    elapsed=$(( elapsed + 5 ))
    [ "$elapsed" -lt "$CHECK_SECS" ] && continue
    elapsed=0

    mb="$(rss_mb_of "$pid")"
    [ -z "$mb" ] && return 0

    if [ "$mb" -ge "$MAX_RSS_MB" ]; then
      echo "[serve-forever] MEMORY CEILING: lfg serve at ${mb}MB >= ${MAX_RSS_MB}MB — restarting it." >&2
      echo "[serve-forever]   This is a leak guard, not a healthy restart. See the 2026-08-07" >&2
      echo "[serve-forever]   freeze note above; raise with LFG_MAX_RSS_MB if the ceiling is wrong." >&2
      terminate "$pid"
      return 1
    fi

    if [ "$warned" -eq 0 ] && [ "$mb" -ge "$WARN_RSS_MB" ]; then
      warned=1
      echo "[serve-forever] lfg serve at ${mb}MB (${WARN_PCT}% of the ${MAX_RSS_MB}MB ceiling)." >&2
    fi
  done
  return 0
}

backoff=1
while [ "$running" -eq 1 ]; do
  start=$(date +%s)
  echo "[serve-forever] starting lfg serve (bun $CUR) — $(date)"
  echo "[serve-forever] memory ceiling ${MAX_RSS_MB}MB, sampled every ${CHECK_SECS}s"
  "$BUN" run src/cli.ts serve &
  child=$!

  supervise "$child"
  hit_ceiling=$?

  wait "$child"
  code=$?
  child=""
  [ "$running" -eq 0 ] && break

  uptime=$(( $(date +%s) - start ))
  if [ "$hit_ceiling" -eq 1 ]; then
    echo "[serve-forever] lfg serve killed at the memory ceiling after ${uptime}s"
  else
    echo "[serve-forever] lfg serve exited (code $code) after ${uptime}s"
  fi

  # Healthy run resets the backoff; a fast crash backs off (cap 30s). A ceiling
  # kill is always a long run, so it restarts immediately — which is the point.
  if [ "$uptime" -ge 30 ]; then
    backoff=1
  else
    backoff=$(( backoff * 2 )); [ "$backoff" -gt 30 ] && backoff=30
  fi
  echo "[serve-forever] restarting in ${backoff}s…"
  sleep "$backoff"
done

echo "[serve-forever] stopped."
