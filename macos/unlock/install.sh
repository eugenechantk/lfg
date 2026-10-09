#!/bin/sh
# Put the lfg unlock plug-in into the macOS screen-unlock rule. Run once, with
# sudo, after build.sh:
#
#   sudo ~/dev/personal/lfg/macos/unlock/install.sh
#
# It adds one branch in FRONT of the existing `system.login.screensaver` rule and
# keeps every existing branch, so typing your password still works exactly as
# before. The rule as it was is saved once to $backup. Undo with uninstall.sh.
# See .claude/feature/mac-unlock.md.
set -eu
[ "$(id -u)" = 0 ] || { echo "install.sh: run with sudo" >&2; exit 1; }
here=$(cd "$(dirname "$0")" && pwd)
bundle="$here/build/LFGUnlockPlugin.bundle"
dest=/Library/Security/SecurityAgentPlugins/LFGUnlockPlugin.bundle
backup=/Library/Security/lfg-unlock-screensaver-rule.backup.plist
right=dev.omg.lfg-unlock.remote
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

[ -d "$bundle" ] || { echo "install.sh: run build.sh first" >&2; exit 1; }
codesign --verify --strict "$bundle"
codesign -dv "$bundle" 2>&1 | grep -q '^TeamIdentifier=39GJBP8V5A$' \
  || { echo "install.sh: plug-in is not signed by team 39GJBP8V5A" >&2; exit 1; }

# 1. The plug-in, root-owned like every other SecurityAgent plug-in.
rm -rf "$dest"
ditto "$bundle" "$dest"
chown -R root:wheel "$dest"
chmod -R go-w "$dest"

# 2. Our branch: run LFGUnlockPlugin:allow (non-privileged, so it runs in the
#    loginwindow SecurityAgent, which is where the helper's socket check expects it).
cat > "$tmp/right.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>class</key><string>evaluate-mechanisms</string>
	<key>comment</key><string>lfg-unlock: allow a screen unlock only while lfg-unlock is asking for one.</string>
	<key>mechanisms</key><array><string>LFGUnlockPlugin:allow</string></array>
	<key>shared</key><true/>
	<key>tries</key><integer>1</integer>
	<key>version</key><integer>1</integer>
</dict>
</plist>
EOF
security authorizationdb write "$right" < "$tmp/right.plist"

# 3. Prepend our branch to system.login.screensaver; any one branch allowing is enough.
security authorizationdb read system.login.screensaver > "$tmp/rule.plist" 2>/dev/null
[ -f "$backup" ] || cp "$tmp/rule.plist" "$backup"
if plutil -extract rule.0 raw -o - "$tmp/rule.plist" >/dev/null 2>&1; then
  if ! plutil -extract rule xml1 -o - "$tmp/rule.plist" | grep -q "<string>$right</string>"; then
    plutil -insert rule.0 -string "$right" "$tmp/rule.plist"
  fi
else
  old=$(plutil -extract rule raw -o - "$tmp/rule.plist")
  plutil -replace rule -json "[\"$right\",\"$old\"]" "$tmp/rule.plist"
fi
plutil -replace k-of-n -integer 1 "$tmp/rule.plist"
security authorizationdb write system.login.screensaver < "$tmp/rule.plist"

# 4. Prove it took.
security authorizationdb read system.login.screensaver 2>/dev/null | plutil -extract rule xml1 -o - - \
  | grep -q "<string>$right</string>" || { echo "install.sh: rule did not take" >&2; exit 1; }
echo "installed. screen-unlock rule now:"
security authorizationdb read system.login.screensaver 2>/dev/null | plutil -p - | sed -n '/"rule" => \[/,/]/p'
