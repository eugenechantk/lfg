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
# The ceiling is measured as PHYS_FOOTPRINT, not `ps` RSS — see `mem_mb_of`.
#
# Tunables:
#   LFG_MAX_RSS_MB     hard ceiling; child is restarted above it   (default 4096)
#   LFG_RSS_WARN_PCT   log a warning at this % of the ceiling      (default 75)
#   LFG_RSS_CHECK_SECS how often to sample the child's memory      (default 30)
#
set -uo pipefail
cd "$(dirname "$0")/.."

# Guarantee the PATH the server needs instead of trusting whoever launched it.
#
# The server shells out to `tmux` BY BARE NAME for everything that makes a
# session steerable — pane discovery (`tmuxTargetForPid`), `send-keys`, spawning
# and resuming sessions — and every one of those calls is inside a try/catch
# that turns "binary not found" into a silent null. On 2026-08-17 the Air's
# server had been (re)started over ssh and inherited sshd's
# PATH=/usr/bin:/bin:/usr/sbin:/sbin. Homebrew's tmux was unreachable, so all 18
# of that host's sessions reported `tmuxTarget: null` and the desktop client
# greyed out every Air row as unopenable (`canOpen == tmuxName != nil`), sends
# 409'd, and resume failed — with the host showing perfectly healthy and green.
# A missing directory on PATH is invisible in every symptom it causes, so fix it
# here rather than depending on the launcher's environment.
for dir in /opt/homebrew/bin /usr/local/bin; do
  case ":$PATH:" in *":$dir:"*) ;; *) [ -d "$dir" ] && PATH="$dir:$PATH" ;; esac
done
export PATH

if ! command -v tmux >/dev/null 2>&1; then
  echo "[serve-forever] WARNING: no tmux on PATH — sessions will report no pane," >&2
  echo "[serve-forever]          and send/resume/spawn will fail on this host." >&2
fi

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

# Sample the child's real memory use in MB. Empty output means it is gone.
#
# NOT `ps -o rss`, which is what this used to do and what made the ceiling fire
# constantly. On macOS, RSS counts pages the allocator has already freed and
# marked reclaimable: the kernel can take them back at no cost and jetsam does
# not charge you for them. Measured on this host 2026-08-16, same instant:
#
#   ps RSS            3326 MB
#   phys_footprint     906 MB      (dirty 911 MB, clean 35 MB, RECLAIMABLE 2471 MB)
#
# Forcing a full GC first proves there is nothing to clean up — `Bun.gc(true)`
# takes heapUsed from 695 MB to 4.7 MB and RSS does not move one megabyte. The
# memory is already free inside the process; only the OS's bookkeeping still
# shows it. So the ceiling was killing a healthy server every few minutes over
# memory it was not using, and each kill drops every /api/events stream — which
# is exactly what the phone reports as "host disconnected" on the go.
#
# phys_footprint is the number jetsam itself uses, so this still catches the real
# 2026-08-07 runaway; it just stops firing on a lie. `footprint` costs ~43 ms.
# Falls back to RSS if it is missing or refuses, so a live child is never
# mistaken for a dead one.
mem_mb_of() {
  local pid="$1" mb kb
  mb="$(/usr/bin/footprint -p "$pid" 2>/dev/null | awk '
    /phys_footprint:/ {
      v = $2; u = $3
      if (u == "GB") printf "%d\n", v * 1024
      else if (u == "MB") printf "%d\n", v
      else if (u == "KB") printf "%d\n", v / 1024
      else printf "%d\n", v / 1048576
      exit
    }')"
  if [ -n "$mb" ]; then echo "$mb"; return; fi
  kb="$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')"
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

    mb="$(mem_mb_of "$pid")"
    [ -z "$mb" ] && return 0

    if [ "$mb" -ge "$MAX_RSS_MB" ]; then
      echo "[serve-forever] MEMORY CEILING: lfg serve at ${mb}MB footprint >= ${MAX_RSS_MB}MB — restarting it." >&2
      echo "[serve-forever]   This is a leak guard, not a healthy restart. See the 2026-08-07" >&2
      echo "[serve-forever]   freeze note above; raise with LFG_MAX_RSS_MB if the ceiling is wrong." >&2
      terminate "$pid"
      return 1
    fi

    if [ "$warned" -eq 0 ] && [ "$mb" -ge "$WARN_RSS_MB" ]; then
      warned=1
      echo "[serve-forever] lfg serve at ${mb}MB footprint (${WARN_PCT}% of the ${MAX_RSS_MB}MB ceiling)." >&2
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
