// Font metric reference (macOS system fonts; SF Mono = monospacedSystemFont).
import AppKit
for (size, w) in [(CGFloat(12), NSFont.Weight.regular), (CGFloat(10.5), NSFont.Weight.regular), (CGFloat(14), NSFont.Weight.semibold)] {
    let f = NSFont.monospacedSystemFont(ofSize: size, weight: w)
    let s = NSAttributedString(string: "W", attributes: [.font: f])
    let ct = f as CTFont
    print(f.fontName, size, "advance", s.size().width, "ascent", CTFontGetAscent(ct), "descent", CTFontGetDescent(ct), "leading", CTFontGetLeading(ct), "capH", CTFontGetCapHeight(ct), "xH", CTFontGetXHeight(ct))
}
for name in ["Menlo-Regular", "Menlo-Bold"] {
    if let f = NSFont(name: name, size: 12) {
        let ct = f as CTFont
        print(name, "adv", NSAttributedString(string: "W", attributes: [.font: f]).size().width, "asc", CTFontGetAscent(ct), "desc", CTFontGetDescent(ct), "capH", CTFontGetCapHeight(ct), "xH", CTFontGetXHeight(ct))
    }
}
