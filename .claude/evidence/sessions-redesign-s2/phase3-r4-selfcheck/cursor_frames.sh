#!/bin/sh
# Sample the terminal cursor pixel across a 2s recording (8 fps) to check it is steady.
S=/private/tmp/claude-501/-Users-eugenechan-dev-personal-lfg/68284ba9-8aab-498d-9c6e-4a97fab2832f/scratchpad/snaps
mkdir -p "$S/curf"
rm -f "$S"/curf/f-*.png 2>/dev/null
ffmpeg -loglevel error -y -i "$S/cur.mov" -vf fps=8 "$S/curf/f-%02d.png"
python3 - "$S" "${1:-73.5}" "${2:-202}" <<'EOF'
import glob, sys
from PIL import Image
s, x, y = sys.argv[1], float(sys.argv[2]), float(sys.argv[3])
vals = [Image.open(f).convert("RGB").getpixel((int(x * 3), int(y * 3)))[0] for f in sorted(glob.glob(s + "/curf/f-*.png"))]
print(len(vals), vals)
EOF
