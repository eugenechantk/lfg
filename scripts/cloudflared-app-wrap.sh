#!/bin/zsh
# cloudflared-app-wrap.sh — wrap Homebrew's cloudflared in ~/Applications/Cloudflared.app
# with a real code-signing identifier (dev.omg.cloudflared).
#
# Why: Surfshark's macOS Bypasser exempts apps by signing identifier. Homebrew's
# cloudflared is linker-signed with identifier "a.out" (like every Go binary), so it
# cannot be exempted. Processes started from this bundle carry dev.omg.cloudflared and
# can be added under Surfshark → Settings → VPN settings → Bypasser → Add app → Open finder.
# Re-run after `brew upgrade cloudflared` (the bundle holds a copy, not a symlink —
# the running process must be the signed file), then `launchctl kickstart -k` the
# tunnel(s) so they pick up the new binary. Idempotent; safe while a tunnel runs.
set -euo pipefail
src="${1:-/opt/homebrew/bin/cloudflared}"
app="$HOME/Applications/Cloudflared.app"
[[ -x "$src" ]] || { print -u2 "no cloudflared at $src"; exit 1 }
# Re-signing rewrites the copy, so compare the source's hash recorded at build time.
stamp="$app/Contents/Resources/source.sha256"
want=$(shasum -a 256 "$src" | cut -d' ' -f1)
if [[ -x "$app/Contents/MacOS/cloudflared" && -f "$stamp" && "$(<"$stamp")" == "$want" ]] \
   && codesign -dv "$app" 2>&1 | grep '^Identifier=dev.omg.cloudflared$' >/dev/null; then
  print "up to date: $app ($("$app/Contents/MacOS/cloudflared" --version))"; exit 0
fi
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
# New inode + rename: a tunnel already running from the bundle keeps its old
# executable (cp -f in place would rewrite the running file and kill it).
tmp="$app/Contents/MacOS/.cloudflared.new.$$"
cp -f "$src" "$tmp" && mv -f "$tmp" "$app/Contents/MacOS/cloudflared"
print -r -- "$want" >| "$stamp"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.omg.cloudflared</string>
  <key>CFBundleName</key><string>Cloudflared</string>
  <key>CFBundleExecutable</key><string>cloudflared</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSUIElement</key><true/>
  <key>LSBackgroundOnly</key><true/>
</dict></plist>
PLIST
codesign -s - -f -i dev.omg.cloudflared "$app" 2>/dev/null
codesign -dv "$app" 2>&1 | grep '^Identifier=dev.omg.cloudflared$' >/dev/null
print "built: $app ($("$app/Contents/MacOS/cloudflared" --version))"
