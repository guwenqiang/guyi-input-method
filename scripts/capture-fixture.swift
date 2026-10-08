import AppKit

final class FixtureDocument: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        for row in 0..<60 {
            let rect = NSRect(x: 12, y: row * 54, width: 720, height: 52)
            guard rect.intersects(dirtyRect) else { continue }
            NSColor(calibratedHue: CGFloat(row % 17) / 17, saturation: 0.13, brightness: 0.98, alpha: 1).setFill()
            rect.fill()
            let text = String(format: "%02d  Hello world. Good morning. Selamat pagi.", row + 1)
            (text as NSString).draw(at: NSPoint(x: 26 + row % 7, y: row * 54 + 12), withAttributes: [.font: NSFont.systemFont(ofSize: 22), .foregroundColor: NSColor.black])
        }
    }
}

final class CaptureFixture: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 760, height: 540), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "GuYi Screenshot Acceptance · Synthetic Content Only"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 760, height: 540))
        scroll.hasVerticalScroller = true
        scroll.documentView = FixtureDocument(frame: NSRect(x: 0, y: 0, width: 740, height: 3240))
        window.contentView = scroll
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

let application = NSApplication.shared
let delegate = CaptureFixture()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
