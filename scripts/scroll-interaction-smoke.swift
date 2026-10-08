import AppKit
@main struct ScrollInteractionSmoke {
    @MainActor static func main() {
        _ = NSApplication.shared
        let panel = ScrollInteractionPanel(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let view = ScrollInteractionView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), selection: NSRect(x: 100, y: 100, width: 300, height: 300), targetPID: getpid())
        panel.contentView = view
        var finished = 0
        view.finish = { finished += 1 }
        func click(_ position: NSPoint, count: Int) -> NSEvent {
            NSEvent.mouseEvent(with: .leftMouseDown, location: position, modifierFlags: [], timestamp: 0, windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: count, pressure: 1)!
        }
        view.mouseDown(with: click(NSPoint(x: 200, y: 200), count: 1))
        precondition(finished == 0, "Single click keeps scrolling capture active")
        view.mouseDown(with: click(NSPoint(x: 20, y: 20), count: 2))
        precondition(finished == 0, "Double click outside selection cannot export")
        view.mouseDown(with: click(NSPoint(x: 200, y: 200), count: 2))
        precondition(finished == 1, "Double click inside selection finishes capture")
        print("PASS · Single click preserves capture; double click only finishes inside selected region")
    }
}
