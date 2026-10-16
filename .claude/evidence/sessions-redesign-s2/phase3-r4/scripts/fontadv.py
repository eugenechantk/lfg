# /// script
# dependencies = ["fonttools"]
# ///
"""Advance width / em and vertical metrics of the Mac's SF Mono and Menlo (reference for the
mono-font exception: is a measured cell pitch explained by the font family or by size?)."""
from fontTools.ttLib import TTFont, TTCollection

def report(name, f):
    upm = f["head"].unitsPerEm
    cmap = f.getBestCmap()
    hm = f["hmtx"]
    adv = hm[cmap[ord("W")]][0]
    os2 = f["OS/2"]
    hh = f["hhea"]
    print(f"{name}: upm {upm} advance(W) {adv} = {adv / upm:.4f} em -> 12pt {12 * adv / upm:.3f}, 10.5pt {10.5 * adv / upm:.3f}; "
          f"capH {getattr(os2, 'sCapHeight', 0) / upm:.3f} em, hhea asc {hh.ascent / upm:.3f} desc {hh.descent / upm:.3f} gap {hh.lineGap / upm:.3f}")
    if "fvar" in f:
        print("   axes", [(a.axisTag, a.minValue, a.defaultValue, a.maxValue) for a in f["fvar"].axes])

report("SFNSMono", TTFont("/System/Library/Fonts/SFNSMono.ttf"))
c = TTCollection("/System/Library/Fonts/Menlo.ttc")
for f in c.fonts:
    report("Menlo " + f["name"].getDebugName(2), f)
