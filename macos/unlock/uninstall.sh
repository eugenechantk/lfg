#!/bin/sh
# Take the lfg unlock plug-in out of the screen-unlock rule. Run with sudo.
# Removes only our branch, so anything else added to the rule since install
# (another app's branch) stays. If the rule is ever broken beyond that, restore
# the saved original by hand:
#   sudo security authorizationdb write system.login.screensaver < /Library/Security/lfg-unlock-screensaver-rule.backup.plist
set -eu
[ "$(id -u)" = 0 ] || { echo "uninstall.sh: run with sudo" >&2; exit 1; }
right=dev.omg.lfg-unlock.remote
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

security authorizationdb read system.login.screensaver > "$tmp/rule.plist" 2>/dev/null
i=0
while v=$(plutil -extract "rule.$i" raw -o - "$tmp/rule.plist" 2>/dev/null); do
  if [ "$v" = "$right" ]; then
    plutil -remove "rule.$i" "$tmp/rule.plist"
    security authorizationdb write system.login.screensaver < "$tmp/rule.plist"
    break
  fi
  i=$((i + 1))
done
security authorizationdb remove "$right" 2>/dev/null || true
rm -rf /Library/Security/SecurityAgentPlugins/LFGUnlockPlugin.bundle
echo "uninstalled. screen-unlock rule now:"
security authorizationdb read system.login.screensaver 2>/dev/null | plutil -p - | sed -n '/"rule" => \[/,/]/p'
