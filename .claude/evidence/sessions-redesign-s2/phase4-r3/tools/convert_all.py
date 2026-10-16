"""Convert every app-*.png window shot from its embedded profile to sRGB (-> *-srgb.png) and print provenance."""
import glob
import hashlib
import io
import os
import sys

from PIL import Image, ImageCms

root = sys.argv[1]
os.chdir(root)
for src in sorted(glob.glob("app-*.png")):
    if src.endswith("-srgb.png"):
        continue
    im = Image.open(src)
    icc = im.info.get("icc_profile")
    desc = "none"
    rgb = im.convert("RGB")
    if icc:
        inp = ImageCms.ImageCmsProfile(io.BytesIO(icc))
        desc = ImageCms.getProfileDescription(inp).strip()
        out = ImageCms.createProfile("sRGB")
        rgb = ImageCms.profileToProfile(rgb, inp, out, outputMode="RGB")
    dst = src.replace(".png", "-srgb.png")
    rgb.save(dst)
    h = hashlib.sha256(open(src, "rb").read()).hexdigest()
    print(f"{src}\t{im.size}\t{im.mode}\tprofile={desc}\tsha256={h}\t-> {dst}")
