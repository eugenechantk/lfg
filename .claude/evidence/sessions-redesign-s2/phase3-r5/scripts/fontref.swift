// Reference rasters of the SF Mono weights at 14pt, 3x, white on #3A3A3C (the key fill),
// to tell which weight the app's key labels use. Writes ../board/fontref-sfmono-<weight>.png
import AppKit

let out = CommandLine.arguments[1]
let weights: [(String, NSFont.Weight)] = [("regular", .regular), ("medium", .medium), ("semibold", .semibold), ("bold", .bold)]
for (name, w) in weights {
    let scale: CGFloat = 3
    let size = NSSize(width: 80, height: 30)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current!.cgContext.setShouldSmoothFonts(false)
    NSGraphicsContext.current!.cgContext.setAllowsFontSmoothing(false)
    NSColor(red: 58 / 255, green: 58 / 255, blue: 60 / 255, alpha: 1).setFill()
    NSRect(origin: .zero, size: size).fill()
    let f = NSFont.monospacedSystemFont(ofSize: 14, weight: w)
    NSAttributedString(string: "ctrl", attributes: [.font: f, .foregroundColor: NSColor.white]).draw(at: NSPoint(x: 4, y: 6))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/fontref-sfmono-\(name).png"))
}
print("ok")
