import AppKit

@main
struct CaptureOverlaySmoke {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let context = CGContext(data: nil, width: 640, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 640, height: 400))
        let view = CaptureSelectionView(frame: NSRect(x: 0, y: 0, width: 640, height: 400), image: context.makeImage()!)
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        var selected: NSRect?
        var cancellations = 0
        view.selected = { selected = $0 }
        view.cancelled = { cancellations += 1 }
        func mouse(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        let initial = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: initial)
        precondition(initial.colorAt(x: initial.pixelsWide/2, y: initial.pixelsHigh/2)!.usingColorSpace(.deviceRGB)!.redComponent < 0.5, "Before selecting, the entire image must be dim")
        var exports = 0
        view.confirmed = { _, _ in exports += 1 }
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 400, y: 300)))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 100, y: 100)))
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let inside = bitmap.colorAt(x: bitmap.pixelsWide / 2, y: bitmap.pixelsHigh / 2)!.usingColorSpace(.deviceRGB)!.redComponent
        let outside = bitmap.colorAt(x: 10, y: 10)!.usingColorSpace(.deviceRGB)!.redComponent
        precondition(inside > 0.95 && outside < 0.7 && outside > 0.3, "Mask must dim outside only")
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: ".build/capture-overlay-fixture.png"))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 100, y: 100)))
        precondition(selected == NSRect(x: 100, y: 100, width: 300, height: 200))
        precondition(exports == 0 && !view.subviews.isEmpty, "Mouse release retains the region and toolbar without export")
        let double = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: 200,y:200), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context:nil, eventNumber:0, clickCount:2, pressure:1)!
        view.mouseDown(with: double)
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x:200,y:200)))
        precondition(exports == 0, "Double-clicking a normal selection must not auto-export")
        var scrollStarts = 0
        view.confirmed = { _, action in if action == .scroll { scrollStarts += 1 } }
        view.beginScroll(at: NSPoint(x: 20, y: 20), deltaY: 20)
        precondition(scrollStarts == 0)
        view.beginScroll(at: NSPoint(x: 200, y: 200), deltaY: 0)
        precondition(scrollStarts == 0)
        view.beginScroll(at: NSPoint(x: 200, y: 200), deltaY: -20)
        view.beginScroll(at: NSPoint(x: 200, y: 200), deltaY: -20)
        precondition(scrollStarts == 1)
        selected = nil
        view.mouseDown(with: mouse(.leftMouseDown, .zero))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 4, y: 4)))
        precondition(selected == nil)
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "\u{1b}",
                                     charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53)!
        view.keyDown(with: escape)
        view.rightMouseDown(with: mouse(.rightMouseDown, .zero))
        precondition(cancellations == 2)
        view.windowRegions = [NSRect(x: 40, y: 40, width: 180, height: 180), NSRect(x: 0, y: 0, width: 500, height: 350)]
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 60, y: 60)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 60, y: 60)))
        precondition(selected == NSRect(x: 40, y: 40, width: 180, height: 180), "Single click chooses frontmost window")
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 220, y: 220)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 260, y: 250)))
        precondition(selected == NSRect(x: 40, y: 40, width: 220, height: 210), "Corner resize preserves opposite corner")
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 120, y: 120)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 150, y: 140)))
        precondition(selected == NSRect(x: 70, y: 60, width: 220, height: 210), "Selection movement preserves size")
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 290, y: 160)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 340, y: 180)))
        precondition(selected == NSRect(x: 70, y: 60, width: 270, height: 210), "Side resize changes width only")
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 200, y: 270)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 210, y: 320)))
        precondition(selected == NSRect(x: 70, y: 60, width: 270, height: 260), "Top resize changes height only")
        let toolbar = view.subviews.last as! NSVisualEffectView
        let stack = toolbar.subviews.first as! NSStackView
        precondition(stack.arrangedSubviews.count == 14, "Annotation tools, history, scroll and export controls")
        let rectangle = stack.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.tag == CaptureTool.rectangle.rawValue }!
        rectangle.performClick(nil)
        view.mouseDown(with: mouse(.leftMouseDown, NSPoint(x: 100, y: 100)))
        view.mouseDragged(with: mouse(.leftMouseDragged, NSPoint(x: 220, y: 200)))
        view.mouseUp(with: mouse(.leftMouseUp, NSPoint(x: 220, y: 200)))
        let annotated = NSBitmapImageRep(cgImage: view.renderedImage()!)
        let red = annotated.colorAt(x: 100, y: 250)!.usingColorSpace(.deviceRGB)!
        precondition(red.redComponent > red.greenComponent + 0.2, "Saved screenshot includes the rectangle stroke")
        let controls = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!.subviews.first as! NSStackView
        controls.arrangedSubviews.compactMap { $0 as? NSButton }.first { $0.tag == 200 }!.performClick(nil)
        let restored = NSBitmapImageRep(cgImage: view.renderedImage()!)
        precondition(restored.colorAt(x: 100, y: 250)!.usingColorSpace(.deviceRGB)!.greenComponent > 0.95, "Undo restores original screenshot pixels")
        var copies = 0
        view.confirmed = { _, action in if action == .copy { copies += 1 } }
        let finalControls = view.subviews.compactMap { $0 as? NSVisualEffectView }.first!.subviews.first as! NSStackView
        (finalControls.arrangedSubviews.last as! NSButton).performClick(nil)
        precondition(copies == 1)
        print("PASS · Overlay dimming, reverse selection, tiny-selection rejection, Escape and right-click cancellation")
    }
}
