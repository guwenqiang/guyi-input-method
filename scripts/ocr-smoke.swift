import AppKit

@main
struct OCRSmoke {
    static func main() throws {
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1000, pixelsHigh: 300,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 1000, height: 300).fill()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 42), .foregroundColor: NSColor.black]
        ("Hello world" as NSString).draw(at: NSPoint(x: 50, y: 190), withAttributes: attributes)
        ("Selamat pagi" as NSString).draw(at: NSPoint(x: 50, y: 90), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        let data = bitmap.representation(using: .png, properties: [:])!
        let regions = try ScreenshotOCR.recognize(data)
        guard regions.contains(where: { $0.text.lowercased().contains("hello world") }),
              regions.contains(where: { $0.text.lowercased().contains("selamat pagi") }),
              regions.allSatisfy({ $0.bounds.width > 0 && $0.bounds.height > 0 && CGRect(x: 0, y: 0, width: 1, height: 1).contains($0.bounds) }) else {
            fatalError("OCR fixture or geometry failed")
        }
        print("PASS · Local OCR recognizes English and Indonesian fixture with normalized text positions")
    }
}
