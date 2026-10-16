"""Copy the coordinator's on-screen captures (phase4-r3-gaps/) to phase4-r3/gaps/<name>-srgb.png, converted from
their embedded profile to sRGB. Originals are not modified."""
import hashlib
import io
import os

from PIL import Image, ImageCms

SRC = "/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase4-r3-gaps"
DST = "/Users/eugenechan/dev/personal/lfg/.claude/worktrees/sessions-redesign-s2/.claude/evidence/sessions-redesign-s2/phase4-r3/gaps"
os.makedirs(DST, exist_ok=True)
for n in ["active-before-click", "after-click-folded", "after-second-click-open", "inactive"]:
    p = os.path.join(SRC, n + ".png")
    im = Image.open(p)
    icc = im.info["icc_profile"]
    rgb = ImageCms.profileToProfile(im.convert("RGB"), ImageCms.ImageCmsProfile(io.BytesIO(icc)),
                                    ImageCms.createProfile("sRGB"), outputMode="RGB")
    out = os.path.join(DST, n + "-srgb.png")
    rgb.save(out)
    print(n, hashlib.sha256(open(p, "rb").read()).hexdigest()[:16], "->", out)
