# /// script
# dependencies = ["pillow"]
# ///
"""Convert PNGs with an embedded ICC profile to sRGB (relative colorimetric). Writes <name>-srgb.png beside each."""
import io, sys
from PIL import Image, ImageCms

for p in sys.argv[1:]:
    im = Image.open(p)
    icc = im.info.get("icc_profile")
    im = im.convert("RGB")
    if not icc:
        print(p, "no profile; copied as-is")
        out = im
    else:
        src = ImageCms.ImageCmsProfile(io.BytesIO(icc))
        dst = ImageCms.createProfile("sRGB")
        out = ImageCms.profileToProfile(im, src, dst, renderingIntent=ImageCms.Intent.RELATIVE_COLORIMETRIC, outputMode="RGB")
        print(p, "converted from", ImageCms.getProfileDescription(src).strip())
    out.save(p[:-4] + "-srgb.png")
