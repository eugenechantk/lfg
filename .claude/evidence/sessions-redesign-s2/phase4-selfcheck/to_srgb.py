"""Convert a window shot from its embedded profile (Display P3) to sRGB, in place copy -> <name>-srgb.png."""
import io
import sys
from PIL import Image, ImageCms

src = sys.argv[1]
im = Image.open(src)
icc = im.info.get("icc_profile")
rgb = im.convert("RGB")
if icc:
    inp = ImageCms.ImageCmsProfile(io.BytesIO(icc))
    out = ImageCms.createProfile("sRGB")
    rgb = ImageCms.profileToProfile(rgb, inp, out, outputMode="RGB")
dst = src.replace(".png", "-srgb.png")
rgb.save(dst)
print(dst, "converted" if icc else "no profile")
