#!/bin/sh
# Build and sign the unlock plug-in and the lfg-unlock helper, then put the
# helper at ~/.lfg/bin/lfg-unlock. Installing the plug-in needs sudo: run
# install.sh afterwards. See .claude/feature/mac-unlock.md.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out="$here/build"
identity="${LFG_UNLOCK_SIGN_IDENTITY:-Developer ID Application: Tsz Kiu Eugene Chan (39GJBP8V5A)}"

rm -rf "$out"
mkdir -p "$out/LFGUnlockPlugin.bundle/Contents/MacOS"
cp "$here/plugin/Info.plist" "$out/LFGUnlockPlugin.bundle/Contents/Info.plist"
clang -bundle -fobjc-arc -O2 -arch arm64 -mmacosx-version-min=13.0 \
  -framework Foundation -framework Security \
  -o "$out/LFGUnlockPlugin.bundle/Contents/MacOS/LFGUnlockPlugin" "$here/plugin/LFGUnlockPlugin.m"
codesign --force --timestamp --options runtime --sign "$identity" "$out/LFGUnlockPlugin.bundle"

swiftc -O -target arm64-apple-macos13 -o "$out/lfg-unlock" "$here/helper/main.swift"
# The plug-in only answers to this identifier signed by this team.
codesign --force --timestamp --options runtime --identifier dev.omg.lfg-unlock --sign "$identity" "$out/lfg-unlock"

codesign --verify --strict "$out/LFGUnlockPlugin.bundle"
codesign --verify --strict "$out/lfg-unlock"
mkdir -p "$HOME/.lfg/bin"
cp "$out/lfg-unlock" "$HOME/.lfg/bin/lfg-unlock"
echo "built: $out/LFGUnlockPlugin.bundle"
echo "installed helper: $HOME/.lfg/bin/lfg-unlock"
