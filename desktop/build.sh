#!/bin/zsh
# Build lfg.app from the single-file SwiftUI source. No Xcode project.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/lfg.app"
ICON_SRC="../ios/LFG/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png"
MODULE_CACHE="build/ModuleCache"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$MODULE_CACHE"

swiftc -O -parse-as-library \
  -module-cache-path "$MODULE_CACHE" \
  -target arm64-apple-macosx26.0 \
  -o "$APP/Contents/MacOS/lfg" \
  LFGSessions.swift

# App icon: reuse the iOS client's 1024px icon, converted to .icns.
if [[ -f "$ICON_SRC" ]]; then
  ICONSET="build/lfg.iconset"
  ICON_TMP="build/AppIcon-sRGB.png"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  rm -f "$ICON_TMP"
  sips -m "/System/Library/ColorSync/Profiles/sRGB Profile.icc" "$ICON_SRC" --out "$ICON_TMP" >/dev/null
  for size in 16 32 128 256 512; do
    sips -z $size $size "$ICON_TMP" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) "$ICON_TMP" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  if ! iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null; then
    python3 - "$ICON_TMP" "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null <<'PY' || true
import sys
from pathlib import Path
from PIL import Image, IcnsImagePlugin

source = Path(sys.argv[1])
output = Path(sys.argv[2])
Image.open(source).convert("RGBA").save(
    output,
    format="ICNS",
    sizes=[(16, 16), (32, 32), (128, 128), (256, 256), (512, 512), (1024, 1024)],
)
PY
  fi
  rm -rf "$ICONSET" "$ICON_TMP"
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>lfg</string>
  <key>CFBundleDisplayName</key><string>lfg</string>
  <key>CFBundleIdentifier</key><string>com.eugenechan.lfg-desktop</string>
  <key>CFBundleExecutable</key><string>lfg</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>26.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <!-- lfg hosts are plain http behind Tailscale -->
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><true/></dict>
  <!-- AppleScript control of iTerm2 -->
  <key>NSAppleEventsUsageDescription</key>
  <string>Opens sessions in iTerm2.</string>
</dict>
</plist>
PLIST

# Prefer a stable signing identity so the TCC automation grant survives
# rebuilds (an ad-hoc signature changes every build and re-prompts).
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk -F'"' '/Developer ID Application/{print $2; exit}')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built: $PWD/$APP"
