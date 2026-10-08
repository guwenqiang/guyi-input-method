import AppKit
import SwiftUI
import GuyiCore

@MainActor
final class AppDelegate {
    static let shared = AppDelegate()
    let preferences = FixturePreferences()
}

struct FixturePreferences {
    var settings = TranslationSettings()
    var apiKey = "fixture-only"
}

@main
struct InlineScreenshotSmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 1200, height: 600, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 600))
        let image = context.makeImage()!
        let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
        let model = ScreenshotTranslation(image: NSImage(cgImage: image, size: .zero), data: png)
        model.cancel()
        model.regions = [.init(text: "Hello world", bounds: CGRect(x: 0.1, y: 0.6, width: 0.4, height: 0.12))]
        model.translatedRegions = [0: "你好，世界"]
        let host = NSHostingView(rootView: InlineScreenshotCanvas(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 600, height: 300)
        host.layoutSubtreeIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let scale = Double(bitmap.pixelsWide) / 600
        let inside = bitmap.colorAt(x: Int(65 * scale), y: Int(86 * scale))!.usingColorSpace(.deviceRGB)!.redComponent
        let outside = bitmap.colorAt(x: Int(10 * scale), y: Int(10 * scale))!.usingColorSpace(.deviceRGB)!.redComponent
        precondition(inside > 0.95 && outside < 0.9, "Translation must cover the normalized original region only")
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/inline-translation-fixture.png"))
        print("PASS · In-place text overlay normalized coordinates and original image extent at Retina scale")
        let panel = ScreenshotTranslationPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        var cancellations = 0
        panel.cancelled = { cancellations += 1 }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: panel.windowNumber, context: nil, characters: "\u{1b}",
                                      charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        panel.keyDown(with: escape)
        panel.cancelOperation(nil)
        precondition(panel.canBecomeKey && !panel.canBecomeMain && cancellations == 2)
        print("PASS · Translation panel accepts Escape without becoming the main application window")
    }
}
