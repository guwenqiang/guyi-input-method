import AppKit
import CoreText

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let iconset = output.appendingPathComponent("Guyi.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
func draw(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let dimension = CGFloat(size)
    NSColor(srgbRed: 0, green: 0, blue: 0, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: dimension * 0.055, y: dimension * 0.055, width: dimension * 0.89, height: dimension * 0.89), xRadius: dimension * 0.18, yRadius: dimension * 0.18).fill()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -dimension * 0.009)
    shadow.shadowBlurRadius = dimension * 0.014
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: dimension * 0.66, weight: .heavy), .foregroundColor: NSColor.white, .shadow: shadow]
    let text = "1" as NSString
    let textSize = text.size(withAttributes: attributes)
    text.draw(at: NSPoint(x: (dimension - textSize.width) / 2, y: (dimension - textSize.height) / 2 + dimension * 0.025), withAttributes: attributes)
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}
for size in [16, 32, 128, 256, 512] {
    try draw(size: size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try draw(size: size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
func menuBadge(scale: Int) -> Data {
    let width = 22 * scale
    let height = 18 * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    let font = CTFontCreateWithName(NSFont.systemFont(ofSize: 13, weight: .heavy).fontName as CFString, 13, nil)
    var character: UniChar = 49
    var glyph: CGGlyph = 0
    CTFontGetGlyphsForCharacters(font, &character, &glyph, 1)
    let letter = CTFontCreatePathForGlyph(font, glyph, nil)!
    let bounds = letter.boundingBoxOfPath
    var transform = CGAffineTransform(translationX: 11 - bounds.midX, y: 9 - bounds.midY)
    let shape = CGMutablePath()
    shape.addRoundedRect(in: CGRect(x: 0, y: 1, width: 22, height: 16), cornerWidth: 4.5, cornerHeight: 4.5)
    context.addPath(shape)
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
    context.fillPath()
    context.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 0.5, color: CGColor(gray: 0, alpha: 0.35))
    context.addPath(letter.copy(using: &transform)!)
    context.setFillColor(CGColor(gray: 1, alpha: 1))
    context.fillPath()
    return bitmap.representation(using: .png, properties: [:])!
}
try menuBadge(scale: 1).write(to: output.appendingPathComponent("input-badge.png"))
try menuBadge(scale: 2).write(to: output.appendingPathComponent("input-badge@2x.png"))
try menuBadge(scale: 1).write(to: output.appendingPathComponent("input-badge-template.png"))
try menuBadge(scale: 2).write(to: output.appendingPathComponent("input-badge-template@2x.png"))
let menuRepresentations = [1, 2].map { scale -> NSBitmapImageRep in
    let representation = NSBitmapImageRep(data: menuBadge(scale: scale))!
    representation.size = NSSize(width: 22, height: 18)
    return representation
}
guard let menuTIFF = NSBitmapImageRep.representationOfImageReps(in: menuRepresentations, using: .tiff, properties: [:]) else { exit(1) }
try menuTIFF.write(to: output.appendingPathComponent("input-menu.tiff"))
try draw(size: 256).write(to: output.appendingPathComponent("logo.png"))
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconset.path, "-o", output.appendingPathComponent("Guyi.icns").path]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else { exit(1) }
try FileManager.default.removeItem(at: iconset)
