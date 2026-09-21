#!/bin/bash
# Headless browser that is ALWAYS a phone-sign-in target.
#
#   scripts/browser-sign-in-headless.sh start ["Browser name"]   -> JSON {id, cdp, targetId, dir, ...}
#   scripts/browser-sign-in-headless.sh list
#   scripts/browser-sign-in-headless.sh stop <id> | --all          (kills it AND deletes its profile)
#
# Why this exists: an agent that launches its own headless Chromium hits login
# walls nobody can get past when Eugene is away from the Mac. Started through
# this script, the browser registers with the local LFG host as a sign-in
# target, so `lfg browser-sign-in request --target <targetId>` puts a sign-in
# panel on his phone and the cookies land in this exact browser.
#
# Why Node, not Bun: playwright-core's connectOverCDP hangs under Bun (measured
# 2026-09-21, bun + playwright-core 1.63; Node connects in ~45 ms). The adapter is
# TypeScript with parameter properties, which Node's type stripping rejects, so it
# is bundled to plain JS with `bun build --target=node` and run under Node.
#
# Drive the browser from Node too: put your .mjs driver in the printed `dir`
# (it has a node_modules symlink, so `import { chromium } from "playwright-core"`
# resolves) and `chromium.connectOverCDP(<cdp>)`.
#
# The profile holds real login sessions. `stop` deletes it. Always stop when done.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$HOME/.lfg/headless"
LFG_URL="${LFG_URL:-http://127.0.0.1:8766}"
export PATH="/opt/homebrew/bin:$HOME/.bun/bin:$PATH"

die() { echo "error: $*" >&2; exit 1; }

find_browser() {
  local b
  b="$(find "$HOME/Library/Caches/ms-playwright" -type f -name chrome-headless-shell 2>/dev/null | sort | tail -1)"
  [ -n "$b" ] && { echo "$b"; return; }
  b="$(find "$HOME/Library/Caches/ms-playwright" -type f -path "*Chromium.app/Contents/MacOS/Chromium" 2>/dev/null | sort | tail -1)"
  [ -n "$b" ] && { echo "$b"; return; }
  die "no Playwright Chromium found. Run: (cd $REPO && bunx playwright-core install chromium)"
}

free_port() {
  local p
  for p in $(seq 9333 9399); do
    # 8766 is LFG's and is outside this range by construction.
    lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1 || { echo "$p"; return; }
  done
  die "no free port in 9333-9399"
}

cmd_start() {
  local name="${1:-Headless}"
  [ -f "$HOME/.lfg/browser-sign-in.token" ] || die "no connection token. Run: (cd $REPO && bun scripts/browser-sign-in-setup.ts >/dev/null)"
  command -v node >/dev/null || die "node not on PATH"
  command -v bun  >/dev/null || die "bun not on PATH"

  local id dir port bin
  id="$(openssl rand -hex 3)"
  dir="$ROOT/$id"
  mkdir -p "$dir/profile"; chmod 700 "$ROOT" "$dir" "$dir/profile"
  port="$(free_port)"
  bin="$(find_browser)"
  local full="$name [$id]"

  local args=(--remote-debugging-port="$port" --remote-debugging-address=127.0.0.1
              --user-data-dir="$dir/profile" --window-size=1440,1000 --no-first-run)
  case "$bin" in *Chromium) args=(--headless=new "${args[@]}");; esac
  nohup "$bin" "${args[@]}" about:blank >"$dir/headless.log" 2>&1 &
  local bpid=$!
  disown "$bpid" 2>/dev/null || true

  local i
  for i in $(seq 1 40); do
    curl -fsS "http://127.0.0.1:$port/json/version" >/dev/null 2>&1 && break
    sleep 0.25
  done
  curl -fsS "http://127.0.0.1:$port/json/version" >/dev/null 2>&1 || { kill "$bpid" 2>/dev/null; rm -rf "$dir"; die "browser did not open its debugging port"; }

  # Fresh bundle every start so it always matches the repo's adapter.
  (cd "$REPO" && bun build scripts/browser-sign-in-playwright.ts --target=node --format=esm \
      --external playwright-core --outfile "$dir/bridge.mjs" >/dev/null)
  ln -sfn "$REPO/node_modules" "$dir/node_modules"
  nohup node --no-warnings "$dir/bridge.mjs" "http://127.0.0.1:$port" "$full" "$LFG_URL" >"$dir/bridge.log" 2>&1 &
  local apid=$!
  disown "$apid" 2>/dev/null || true

  for i in $(seq 1 60); do
    grep -q "Phone sign-in: connected" "$dir/bridge.log" 2>/dev/null && break
    kill -0 "$apid" 2>/dev/null || break
    sleep 0.25
  done
  if ! grep -q "Phone sign-in: connected" "$dir/bridge.log" 2>/dev/null; then
    kill "$apid" "$bpid" 2>/dev/null || true
    echo "--- bridge.log" >&2; head -5 "$dir/bridge.log" >&2 || true
    rm -rf "$dir"
    die "adapter did not connect to LFG at $LFG_URL (is the host running?)"
  fi

  local target
  target="$(cd "$REPO" && bun src/cli.ts browser-sign-in targets | NAME="$full" node -e '
    let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{
      const t=(JSON.parse(s).targets||[]).find(x=>x.name===process.env.NAME);process.stdout.write(t?t.id:"")})')"
  [ -n "$target" ] || { kill "$apid" "$bpid" 2>/dev/null || true; rm -rf "$dir"; die "registered but not listed as a target"; }

  printf '{"id":"%s","name":"%s","cdp":"http://127.0.0.1:%s","targetId":"%s","dir":"%s","browserPid":%s,"adapterPid":%s}\n' \
    "$id" "$full" "$port" "$target" "$dir" "$bpid" "$apid" | tee "$dir/state.json"
}

cmd_list() {
  local f any=0
  for f in "$ROOT"/*/state.json; do
    [ -f "$f" ] || continue
    any=1
    local bpid; bpid="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1])).browserPid))' "$f")"
    if kill -0 "$bpid" 2>/dev/null; then cat "$f"; else echo "{\"stale\":\"$(dirname "$f")\"}"; fi
  done
  [ "$any" = 1 ] || echo '{"sessions":[]}'
}

stop_one() {
  local dir="$ROOT/$1"
  [ -d "$dir" ] || die "no such session: $1"
  if [ -f "$dir/state.json" ]; then
    local pids
    pids="$(node -e 'const s=JSON.parse(require("fs").readFileSync(process.argv[1]));process.stdout.write(s.adapterPid+" "+s.browserPid)' "$dir/state.json")"
    # shellcheck disable=SC2086
    kill $pids 2>/dev/null || true
    sleep 1
    # shellcheck disable=SC2086
    kill -9 $pids 2>/dev/null || true
  fi
  rm -rf "$dir"          # the profile holds login sessions — never leave it behind
  echo "stopped $1 and deleted its profile"
}

cmd_stop() {
  [ $# -ge 1 ] || die "usage: stop <id> | --all"
  if [ "$1" = "--all" ]; then
    local d
    for d in "$ROOT"/*/; do [ -d "$d" ] && stop_one "$(basename "$d")"; done
  else
    stop_one "$1"
  fi
}

case "${1:-}" in
  start) shift; cmd_start "$@";;
  list)  cmd_list;;
  stop)  shift; cmd_stop "$@";;
  *) sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 2;;
esac
