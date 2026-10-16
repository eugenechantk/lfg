#!/bin/sh
# Extract the last frame of app/<name>.mov to app/<name>.png and print its size + hash.
D=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r13/app
ffmpeg -y -loglevel error -i "$D/$1.mov" -update 1 "$D/$1.png" || exit 1
sips -g pixelWidth -g pixelHeight "$D/$1.png" | tail -2 | tr '\n' ' '
shasum -a 256 "$D/$1.png" | cut -c1-16
date +%T
