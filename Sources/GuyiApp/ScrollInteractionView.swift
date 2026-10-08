import AppKit

final class ScrollInteractionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class ScrollInteractionView: NSView {
    let selectedRect: NSRect
    let targetPID: pid_t
    var scroll: ((NSEvent) -> Void)?
    var finish: (() -> Void)?
    var cancel: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(frame:NSRect, selection:NSRect, targetPID:pid_t) {
        self.selectedRect=selection;self.targetPID=targetPID
        super.init(frame:frame)
    }
    required init?(coder:NSCoder){fatalError()}
    override func draw(_ dirtyRect:NSRect){
        // A fully transparent hole is click-through at the WindowServer level.
        // Keep a nearly invisible hit surface so double-click/wheel reach this
        // view; capture excludes this app, so saved pixels remain unmodified.
        NSColor.black.withAlphaComponent(0.01).setFill()
        selectedRect.fill()
        NSColor.black.withAlphaComponent(0.5).setFill()
        let mask=NSBezierPath(rect:bounds);mask.appendRect(selectedRect);mask.windingRule = .evenOdd;mask.fill()
        NSColor.systemBlue.setStroke();let edge=NSBezierPath(rect:selectedRect);edge.lineWidth=2;edge.stroke()
    }
    override func scrollWheel(with event:NSEvent){
        guard selectedRect.contains(convert(event.locationInWindow,from:nil)),NSRunningApplication(processIdentifier:targetPID) != nil else{return}
        scroll?(event)
    }
    override func mouseDown(with event:NSEvent){
        if event.clickCount==2,selectedRect.contains(convert(event.locationInWindow,from:nil)){finish?()}
    }
    override func rightMouseDown(with event:NSEvent){cancel?()}
    override func keyDown(with event:NSEvent){
        if event.keyCode==53{cancel?()}
        else if [36,76].contains(event.keyCode){finish?()}
    }
}
