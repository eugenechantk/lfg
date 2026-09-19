#!/bin/bash
# SUPERSEDED on the Pro 2026-09-18: the tunnel now bypasses the VPN with
# cloudflared's --edge-bind-address via ~/.cloudflared/lfg-pro-run.sh
# (scripts/cloudflared-edge-bind-run.sh), which needs no Surfshark Bypasser.
# Keep this for the bundle-based approach the Air still uses.
# Put the lfg-pro cloudflared daemon back OUTSIDE Surfshark (the 09-10 setup),
# after Eugene has fixed the Surfshark side. Refuses to proceed while the
# bypassed bundle path still carries no packets, so it can't strand the tunnel.
#
# Background: .claude/feature/cloudflared-surfshark-bypass.md (the setup) and
# .claude/diagnosis-media-slow-tunnel-in-vpn-20260917.md (why it matters —
# inside the VPN the tunnel runs at 50–90 KB/s with a 400 ms edge RTT).
#
# Prereqs in the Surfshark app (both need the GUI): Kill Switch OFF, Bypasser ON
# with ~/Applications/Cloudflared.app listed, then reconnect the VPN.
#
# Usage: scripts/cloudflared-restore-bypass.sh [--dry-run]
set -euo pipefail

AGENT_LABEL="dev.omg.lfg-cloudflared"
PLIST="$HOME/Library/LaunchAgents/$AGENT_LABEL.plist"
BUNDLE_BIN="$HOME/Applications/Cloudflared.app/Contents/MacOS/cloudflared"
BREW_BIN="/opt/homebrew/bin/cloudflared"
DRY_RUN="${1:-}"

say() { printf '%s\n' "$*"; }
fail() { say "✗ $*"; exit 1; }

[[ -x "$BUNDLE_BIN" ]] || fail "no wrapper at $BUNDLE_BIN — run scripts/cloudflared-app-wrap.sh first"
[[ -f "$PLIST" ]] || fail "no LaunchAgent plist at $PLIST"

# 1. Is the bundle actually BYPASSED? Surfshark's Bypasser keys on the signing
#    id, so only something run FROM the bundle sees the bypassed route. A
#    `curl` copied into the bundle asks Cloudflare which public IP it arrived
#    from; that must differ from the VPN exit (what /usr/bin/curl reports) and
#    match the direct Wi-Fi exit. With Bypasser off the bundle rides the VPN
#    and this test fails — which is the point: a dig-style "does it resolve"
#    probe passes in that state and would strand the tunnel inside the VPN.
PROBE_DIR="$HOME/Applications/Cloudflared.app/Contents/MacOS"
PROBE="$PROBE_DIR/curl"
if [[ ! -x "$PROBE" ]]; then
  cp /usr/bin/curl "$PROBE"
  codesign --force --sign - --identifier dev.omg.cloudflared "$PROBE" >/dev/null 2>&1 || true
fi
TRACE="https://speed.cloudflare.com/cdn-cgi/trace"
exit_ip() { "$@" -s -m 8 "$TRACE" 2>/dev/null | awk -F= '$1=="ip"{print $2}'; }
say "• probing egress: bundle vs VPN vs direct Wi-Fi…"
BUNDLE_IP=$(exit_ip "$PROBE" || true)
VPN_IP=$(exit_ip /usr/bin/curl || true)
DIRECT_IP=$(exit_ip /usr/bin/curl --interface en0 || true)
say "  bundle=$BUNDLE_IP  default-route=$VPN_IP  en0=$DIRECT_IP"
[[ -n "$BUNDLE_IP" ]] || fail "the bundle path carries no packets — Kill Switch is dropping bypassed apps, or Bypasser is mis-set. Fix Surfshark first."
if [[ -n "$DIRECT_IP" && "$BUNDLE_IP" != "$DIRECT_IP" ]]; then
  fail "the bundle still exits via $BUNDLE_IP (the VPN), not $DIRECT_IP — Bypasser is off. Turn it on for Cloudflared.app and reconnect, then rerun."
fi
say "✓ bundle traffic leaves via the direct interface ($BUNDLE_IP)"

# 2. Point the agent at the bundle binary (idempotent).
if grep -q "$BUNDLE_BIN" "$PLIST"; then
  say "• plist already runs the bundle binary"
else
  cp "$PLIST" "$PLIST.bak-$(date +%Y%m%d-%H%M%S)-restore"
  if [[ "$DRY_RUN" == "--dry-run" ]]; then
    say "• dry-run: would rewrite $PLIST → $BUNDLE_BIN"
  else
    /usr/bin/sed -i '' "s|<string>$BREW_BIN</string>|<string>$BUNDLE_BIN</string>|" "$PLIST"
    grep -q "$BUNDLE_BIN" "$PLIST" || fail "plist rewrite did not take"
    say "✓ plist → $BUNDLE_BIN"
  fi
fi

[[ "$DRY_RUN" == "--dry-run" ]] && { say "dry-run done"; exit 0; }

# 3. Reload: bootout → wait until gone → bootstrap (kickstart does NOT re-read
#    the plist, per the 09-10 notes).
UID_NUM=$(id -u)
say "• reloading $AGENT_LABEL…"
launchctl bootout "gui/$UID_NUM/$AGENT_LABEL" 2>/dev/null || true
for _ in $(seq 1 20); do
  launchctl print "gui/$UID_NUM/$AGENT_LABEL" >/dev/null 2>&1 || break
  sleep 0.5
done
launchctl bootstrap "gui/$UID_NUM" "$PLIST"

# 4. Verify: edge sockets must come from the LAN address, not 10.14.x (VPN).
say "• waiting for edge connections…"
for _ in $(seq 1 30); do
  sleep 1
  if netstat -anv -p tcp 2>/dev/null | grep -q '7844 .*ESTABLISHED'; then break; fi
done
netstat -anv -p tcp | awk '$5 ~ /\.7844$/ && $6=="ESTABLISHED" {print "  " $4 " -> " $5}'
if netstat -anv -p tcp | awk '$5 ~ /\.7844$/ && $6=="ESTABLISHED" {print $4}' | grep -q '^10\.14\.'; then
  fail "edge sockets still originate from the VPN address — tunnel is not bypassed"
fi
say "✓ edge connections leave via the LAN interface"
say "Next: a 3 MB range through https://lfg-pro.eugenechantk.me/api/file should now run at MB/s (measure from another machine — from the Pro itself the request rides the VPN out and back)."
