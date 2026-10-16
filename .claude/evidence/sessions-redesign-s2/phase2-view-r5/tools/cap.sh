#!/bin/sh
# cap.sh <name> : record 1 s of the sim, keep the last frame as app/<name>.png (lossy h264 source)
D=/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase2-view-r5/app
rm -f "$D/$1.mov"
flowdeck ui simulator record -S "C47EB72F-A352-44C9-8A80-9F13D33780AD" --duration 1 --codec h264 --force --output "$D/$1.mov" >/dev/null 2>&1
if [ ! -s "$D/$1.mov" ]; then echo "NO MOV for $1"; exit 1; fi
ffmpeg -y -loglevel error -i "$D/$1.mov" -update 1 "$D/$1.png"
rm -f "$D/$1.mov"
python3 -c "import struct,sys;f=open(sys.argv[1],'rb');f.read(16);w,h=struct.unpack('>II',f.read(8));print(sys.argv[1].split('/')[-1],w,h)" "$D/$1.png"
date +%T
