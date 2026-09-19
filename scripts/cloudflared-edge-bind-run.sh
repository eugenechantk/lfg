#!/bin/bash
# lfg-pro cloudflared launcher for a Mac that runs a VPN (Surfshark).
#
# Binds cloudflared's edge connections to the Wi-Fi address. macOS scopes a
# socket's route to the interface that owns its bound source address, so the
# tunnel leaves via en0 instead of the VPN's utun default route — no root, no
# Surfshark Bypasser (which the Pro's kill-switch firewall black-holes anyway).
# Measured 2026-09-18: 360 ms → 29 ms edge RTT, tunnel throughput 37 KB/s → MB/s.
#
# If the interface has no address (Wi-Fi down) it runs unbound, i.e. through the
# VPN, so the tunnel still comes up. If the address changes while running, the
# wrapper exits and launchd (KeepAlive) respawns it with the new bind.
#
# Live copy: ~/.cloudflared/lfg-pro-run.sh (LaunchAgent dev.omg.lfg-cloudflared).
set -u
CF=${LFG_CLOUDFLARED_BIN:-/opt/homebrew/bin/cloudflared}
CFG=${LFG_CLOUDFLARED_CONFIG:-$HOME/.cloudflared/lfg-pro.yml}
TUNNEL=${LFG_CLOUDFLARED_TUNNEL:-lfg-pro}
IFACE=${LFG_EDGE_IFACE:-en0}

log() { echo "$(date -u +%FT%TZ) INF lfg-pro-run: $*"; }

ip=$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)
args=(tunnel --config "$CFG")
if [[ -n $ip ]]; then
  args+=(--edge-bind-address "$ip")
  log "binding edge connections to $IFACE $ip"
else
  log "no address on $IFACE; running unbound (VPN path)"
fi
args+=(run "$TUNNEL")

"$CF" "${args[@]}" &
child=$!
trap 'kill -TERM "$child" 2>/dev/null; wait "$child"; exit 0' TERM INT

while kill -0 "$child" 2>/dev/null; do
  sleep 30
  now=$(ipconfig getifaddr "$IFACE" 2>/dev/null || true)
  if [[ $now != "$ip" ]]; then
    log "$IFACE address changed ($ip -> ${now:-none}); restarting for a fresh bind"
    kill -TERM "$child" 2>/dev/null; wait "$child"; exit 0
  fi
done
wait "$child"
