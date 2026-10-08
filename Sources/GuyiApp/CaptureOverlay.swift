import AppKit
import ScreenCaptureKit
import GuyiCore
import CoreImage

enum CaptureAction: Int { case copy, save, translate, scroll }

@MainActor
final class CaptureOverlay {
    private var panels: [NSPanel] = []
    private var completion: ((CGImage, CGRect, CaptureAction, CGEvent?, (pid_t, CGWindowID)?) -> Void)?
    var cancelled: (() -> Void)?

    func start(completion: @escaping (CGImage, CGRect, CaptureAction, CGEvent?, (pid_t, CGWindowID)?) -> Void) async throws {
        self.completion = completion
        var snapshots: [(NSScreen, CGImage)] = []
        let mainHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let visibleWindows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windowRects = visibleWindows.compactMap { entry -> CGRect? in
            guard entry[kCGWindowOwnerPID as String] as? Int32 != getpid(),
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let values = entry[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: values as CFDictionary), rect.width >= 80, rect.height >= 60 else { return nil }
            return rect
        }
        for screen in NSScreen.screens {
            let frame = screen.frame
            let rect = CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
            // Obtain the same permission used by scrolling before showing any
            // screen-covering panels, so system consent is never behind a mask.
            let capture = try await ScrollRegionCapture.prepare(rect: rect,
                pixelSize: CGSize(width: frame.width * screen.backingScaleFactor,
                                  height: frame.height * screen.backingScaleFactor))
            let image = try await capture.capture()
            snapshots.append((screen, image))
        }
        for (screen, image) in snapshots {
            let panel = CapturePanel(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            panel.level = .screenSaver
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.acceptsMouseMovedEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let view = CaptureSelectionView(frame: NSRect(origin: .zero, size: screen.frame.size), image: image)
            view.pointer = NSPoint(x: NSEvent.mouseLocation.x - screen.frame.minX,
                                   y: NSEvent.mouseLocation.y - screen.frame.minY)
            view.windowRegions = windowRects.compactMap { rect in
                let local = CGRect(x: rect.minX - screen.frame.minX, y: mainHeight - rect.maxY - screen.frame.minY,
                                   width: rect.width, height: rect.height).intersection(view.bounds)
                return local.width >= 16 && local.height >= 16 ? local : nil
            }
            view.cancelled = { [weak self] in self?.close(); self?.cancelled?() }
            view.confirmed = { [weak self, weak view] selection, action in
                guard let view else { return }
                let scaleX = CGFloat(image.width) / screen.frame.width
                let scaleY = CGFloat(image.height) / screen.frame.height
                let crop = CGRect(x: selection.minX * scaleX, y: (screen.frame.height - selection.maxY) * scaleY,
                                  width: selection.width * scaleX, height: selection.height * scaleY).integral
                guard let rendered = view.renderedImage(), let cropped = rendered.cropping(to: crop) else { return }
                let global = CGRect(x: screen.frame.minX + crop.minX / scaleX,
                                    y: mainHeight - screen.frame.maxY + crop.minY / scaleY,
                                    width: crop.width / scaleX, height: crop.height / scaleY)
                let center = CGPoint(x: global.midX, y: global.midY)
                let target = visibleWindows.first { entry in
                    guard entry[kCGWindowOwnerPID as String] as? Int32 != getpid(),
                          entry[kCGWindowLayer as String] as? Int == 0,
                          let values = entry[kCGWindowBounds as String] as? [String: Any],
                          let rect = CGRect(dictionaryRepresentation: values as CFDictionary) else { return false }
                    return rect.contains(center)
                }
                let identity: (pid_t, CGWindowID)? = target.flatMap { entry in
                    guard let pid = entry[kCGWindowOwnerPID as String] as? Int32,
                          let window = entry[kCGWindowNumber as String] as? UInt32 else { return nil }
                    return (pid, window)
                }
                self?.close()
                self?.completion?(cropped, global, action, view.initialScrollEvent, identity)
            }
            panel.contentView = view
            panels.append(panel)
            panel.makeKeyAndOrderFront(nil)
            panel.makeFirstResponder(view)
            panel.invalidateCursorRects(for: view)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { panels.forEach { $0.close() }; panels.removeAll() }
}

private final class CapturePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class CaptureSelectionView: NSView, NSTextFieldDelegate {
    let image: NSImage
    private let originalImage: CGImage
    private var marks: [CaptureMark] = []
    private var undone: [CaptureMark] = []
    private var drawing: CaptureMark?
    private var tool = CaptureTool.selection
    private var markColor = NSColor.systemRed
    private var markWidth: CGFloat = 3
    private var colorToolbar: NSView?
    private var textEditor: NSTextField?
    var pointer = NSPoint.zero
    private lazy var pixelated: NSImage? = {
        let ci = CIImage(cgImage: originalImage).applyingFilter("CIPixellate", parameters: [kCIInputScaleKey: 14])
        guard let result = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
        return NSImage(cgImage: result, size: bounds.size)
    }()
    private var anchor = NSPoint.zero
    private var selection = NSRect.zero
    private var toolbar: NSView?
    private var movingFrom: NSRect?
    private var resizeFrom: NSRect?
    private var resizeEdges: (horizontal: Int, vertical: Int)?
    private var completed = false
    private var hovered = NSRect.zero
    private var clickRegion = NSRect.zero
    private var tracking: NSTrackingArea?
    var windowRegions: [NSRect] = []
    var selected: ((NSRect) -> Void)?
    var confirmed: ((NSRect, CaptureAction) -> Void)?
    var cancelled: (() -> Void)?
    private(set) var initialScrollEvent: CGEvent?
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    init(frame: NSRect, image: CGImage) {
        self.originalImage = image
        self.image = NSImage(cgImage: image, size: frame.size)
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
        if !selection.isEmpty, tool == .selection {
            addCursorRect(selection.insetBy(dx: 8, dy: 8), cursor: .openHand)
            addCursorRect(NSRect(x: selection.minX-5, y: selection.minY, width: 10, height: selection.height), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: selection.maxX-5, y: selection.minY, width: 10, height: selection.height), cursor: .resizeLeftRight)
            addCursorRect(NSRect(x: selection.minX, y: selection.minY-5, width: selection.width, height: 10), cursor: .resizeUpDown)
            addCursorRect(NSRect(x: selection.minX, y: selection.maxY-5, width: selection.width, height: 10), cursor: .resizeUpDown)
        }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(tracking)
        self.tracking = tracking
    }
    override func mouseMoved(with event: NSEvent) {
        pointer = convert(event.locationInWindow, from: nil)
        needsDisplay = true
        guard selection.isEmpty else { return }
        let point = pointer
        let rect = windowRegions.first(where: { $0.contains(point) }) ?? .zero
        if hovered != rect { hovered = rect; needsDisplay = true }
    }
    override func draw(_ dirtyRect: NSRect) {
        image.draw(in: bounds)
        NSColor.black.withAlphaComponent(0.60).setFill()
        let mask = NSBezierPath(rect: bounds)
        let highlighted = selection.isEmpty ? hovered : selection
        if !selection.isEmpty { mask.appendRect(selection) }
        mask.windingRule = .evenOdd
        mask.fill()
        if !highlighted.isEmpty {
            NSColor.systemBlue.setStroke()
            let border = NSBezierPath(rect: highlighted)
            border.lineWidth = 1
            border.stroke()
            if !selection.isEmpty {
                drawMarks()
                NSColor.systemBlue.setFill()
                for point in handles(of: selection) {
                    NSBezierPath(rect: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6)).fill()
                }
                let size = "\(Int(selection.width * CGFloat(originalImage.width) / bounds.width)) × \(Int(selection.height * CGFloat(originalImage.height) / bounds.height))"
                let box = NSRect(x: selection.minX, y: min(bounds.maxY-22,selection.maxY+4), width: 140, height: 20)
                NSColor.black.withAlphaComponent(0.65).setFill();NSBezierPath(roundedRect:box,xRadius:4,yRadius:4).fill()
                (size as NSString).draw(at:NSPoint(x:box.minX+6,y:box.minY+3),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.medium),.foregroundColor:NSColor.white])
            }
        }
        if selection.isEmpty { drawMagnifier() }
    }
    override func mouseDown(with event: NSEvent) {
        anchor = convert(event.locationInWindow, from: nil)
        finishText()
        if !selection.isEmpty, tool != .selection, selection.contains(anchor) {
            if tool == .text { beginText(at: anchor); return }
            drawing = CaptureMark(tool:tool,points:[anchor],color:markColor,width:markWidth)
            return
        }
        clickRegion = windowRegions.first(where: { $0.contains(anchor) }) ?? bounds
        // Choosing or adjusting a region never exports it. Export actions stay in
        // the selection toolbar; double-click completion belongs to scroll capture.
        completed = false
        toolbar?.removeFromSuperview()
        toolbar = nil
        colorToolbar?.removeFromSuperview(); colorToolbar = nil
        resizeFrom = nil
        resizeEdges = nil
        if !selection.isEmpty, let edges = edges(at: anchor) {
            resizeFrom = selection
            resizeEdges = edges
            movingFrom = nil
            return
        }
        movingFrom = selection.contains(anchor) && !selection.isEmpty ? selection : nil
        if movingFrom != nil { return }
        selection = .zero
        marks = []; undone = []
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if drawing != nil {
            let p=NSPoint(x:max(selection.minX,min(point.x,selection.maxX)),y:max(selection.minY,min(point.y,selection.maxY)))
            if tool == .pen { drawing?.points.append(p) }
            else { drawing?.points = [anchor,p] }
            needsDisplay = true
            return
        }
        if textEditor != nil { return }
        hovered = .zero
        if let resizeFrom, let resizeEdges {
            var left = resizeFrom.minX, right = resizeFrom.maxX
            var bottom = resizeFrom.minY, top = resizeFrom.maxY
            if resizeEdges.horizontal < 0 { left = min(max(0, point.x), right - 16) }
            if resizeEdges.horizontal > 0 { right = max(min(bounds.maxX, point.x), left + 16) }
            if resizeEdges.vertical < 0 { bottom = min(max(0, point.y), top - 16) }
            if resizeEdges.vertical > 0 { top = max(min(bounds.maxY, point.y), bottom + 16) }
            selection = NSRect(x: left, y: bottom, width: right - left, height: top - bottom)
        } else if let movingFrom {
            let old = selection.origin
            selection = movingFrom
            selection.origin = NSPoint(x: max(0, min(bounds.width - selection.width, movingFrom.minX + point.x - anchor.x)),
                                       y: max(0, min(bounds.height - selection.height, movingFrom.minY + point.y - anchor.y)))
            let dx=selection.minX-old.x, dy=selection.minY-old.y
            for i in marks.indices { marks[i].points=marks[i].points.map { NSPoint(x:$0.x+dx,y:$0.y+dy) } }
        } else {
            selection = NSRect(x: min(anchor.x, point.x), y: min(anchor.y, point.y),
                               width: abs(point.x - anchor.x), height: abs(point.y - anchor.y)).intersection(bounds)
        }
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        if let drawing {
            marks.append(drawing); self.drawing=nil; undone=[]; needsDisplay=true; showToolbar(); return
        }
        if textEditor != nil { return }
        let point = convert(event.locationInWindow, from: nil)
        if movingFrom == nil, resizeFrom == nil, abs(point.x - anchor.x) < 3, abs(point.y - anchor.y) < 3 {
            selection = clickRegion
            needsDisplay = true
        } else { mouseDragged(with: event) }
        movingFrom = nil
        resizeFrom = nil
        resizeEdges = nil
        if selection.width >= 16 && selection.height >= 16 { selected?(selection); showToolbar() }
        window?.invalidateCursorRects(for: self)
    }
    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.contains(.command), event.keyCode == 6 {
            undoMark(redo:event.modifierFlags.contains(.shift)); return
        }
        if event.keyCode == 53 { cancelled?() }
        else if !selection.isEmpty, event.keyCode == 36 || event.keyCode == 76 || (event.keyCode == 8 && event.modifierFlags.contains(.command)) {
            confirm(.copy)
        }
    }
    override func rightMouseDown(with event: NSEvent) { cancelled?() }
    private func handles(of rect: NSRect) -> [NSPoint] {
        [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.maxX, y: rect.minY),
         NSPoint(x: rect.minX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY),
         NSPoint(x: rect.midX, y: rect.minY), NSPoint(x: rect.midX, y: rect.maxY),
         NSPoint(x: rect.minX, y: rect.midY), NSPoint(x: rect.maxX, y: rect.midY)]
    }
    private func edges(at point: NSPoint) -> (horizontal: Int, vertical: Int)? {
        guard selection.insetBy(dx: -8, dy: -8).contains(point) else { return nil }
        let horizontal = abs(point.x - selection.minX) <= 8 ? -1 : (abs(point.x - selection.maxX) <= 8 ? 1 : 0)
        let vertical = abs(point.y - selection.minY) <= 8 ? -1 : (abs(point.y - selection.maxY) <= 8 ? 1 : 0)
        return horizontal != 0 || vertical != 0 ? (horizontal, vertical) : nil
    }
    override func scrollWheel(with event: NSEvent) {
        initialScrollEvent = event.cgEvent?.copy()
        beginScroll(at: convert(event.locationInWindow, from: nil), deltaY: event.scrollingDeltaY)
    }
    func beginScroll(at point: NSPoint, deltaY: CGFloat) {
        guard marks.isEmpty, textEditor == nil, toolbar != nil, selection.width >= 16, selection.height >= 16, selection.contains(point), abs(deltaY) > 0.01 else { return }
        confirm(.scroll)
    }
    private func confirm(_ action: CaptureAction) {
        finishText()
        guard !completed, selection.width >= 16, selection.height >= 16 else { return }
        completed = true
        confirmed?(selection, action)
    }
    private func drawMarks() {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(rect: selection).addClip()
        for mark in marks { mark.draw(pixelated: mark.tool == .mosaic ? pixelated : nil, bounds: bounds) }
        drawing?.draw(pixelated: drawing?.tool == .mosaic ? pixelated : nil, bounds: bounds)
        NSGraphicsContext.restoreGraphicsState()
    }
    func renderedImage() -> CGImage? {
        guard !marks.isEmpty else { return originalImage }
        guard let context = CGContext(data:nil,width:originalImage.width,height:originalImage.height,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.scaleBy(x:CGFloat(originalImage.width)/bounds.width,y:CGFloat(originalImage.height)/bounds.height)
        let previous=NSGraphicsContext.current
        NSGraphicsContext.current=NSGraphicsContext(cgContext:context,flipped:false)
        image.draw(in:bounds)
        drawMarks()
        NSGraphicsContext.current=previous
        return context.makeImage()
    }
    private func drawMagnifier() {
        guard bounds.contains(pointer), pointer != .zero else { return }
        let box=NSRect(x:min(max(8,pointer.x+18),bounds.maxX-150),y:min(max(8,pointer.y-155),bounds.maxY-145),width:142,height:138)
        NSColor.white.setFill(); NSBezierPath(roundedRect:box,xRadius:7,yRadius:7).fill()
        let source=NSRect(x:max(0,min(bounds.maxX-24,pointer.x-12)),y:max(0,min(bounds.maxY-24,pointer.y-12)),width:24,height:24)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current?.imageInterpolation = .none
        let zoom=NSRect(x:box.minX+7,y:box.minY+31,width:128,height:100)
        NSBezierPath(rect:zoom).addClip()
        image.draw(in:zoom,from:source,operation:.copy,fraction:1)
        NSColor.systemBlue.setStroke()
        let cross=NSBezierPath();cross.move(to:NSPoint(x:zoom.midX,y:zoom.minY));cross.line(to:NSPoint(x:zoom.midX,y:zoom.maxY))
        cross.move(to:NSPoint(x:zoom.minX,y:zoom.midY));cross.line(to:NSPoint(x:zoom.maxX,y:zoom.midY));cross.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let caption="\(Int(pointer.x)) × \(Int(bounds.height-pointer.y))"
        (caption as NSString).draw(at:NSPoint(x:box.minX+8,y:box.minY+9),withAttributes:[.font:NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular),.foregroundColor:NSColor.black])
    }
    private func beginText(at point:NSPoint) {
        let editor=NSTextField(frame:NSRect(x:point.x,y:max(selection.minY,point.y-26),width:max(60,min(240,selection.maxX-point.x)),height:28))
        editor.font = .systemFont(ofSize:max(16,markWidth*6))
        editor.textColor=markColor
        editor.placeholderString=Localizer.text("输入标注文字")
        editor.delegate=self
        editor.target=self;editor.action=#selector(textConfirmed(_:))
        addSubview(editor);textEditor=editor
        window?.makeFirstResponder(editor)
    }
    @objc private func textConfirmed(_ sender:Any?) { finishText() }
    func controlTextDidEndEditing(_ notification:Notification) { finishText() }
    private func finishText() {
        guard let editor=textEditor else{return}
        textEditor=nil
        let text=editor.stringValue
        if !text.isEmpty { marks.append(CaptureMark(tool:.text,points:[NSPoint(x:editor.frame.minX,y:editor.frame.maxY)],color:markColor,width:markWidth,text:text));undone=[] }
        editor.removeFromSuperview();window?.makeFirstResponder(self);needsDisplay=true
    }
    private func undoMark(redo:Bool) {
        finishText()
        if redo { if let mark=undone.popLast(){marks.append(mark)} }
        else { if let mark=marks.popLast(){undone.append(mark)} }
        needsDisplay=true;showToolbar()
    }
    private func showToolbar() {
        toolbar?.removeFromSuperview();colorToolbar?.removeFromSuperview();colorToolbar=nil
        let stack=NSStackView();stack.orientation = .horizontal;stack.spacing=3
        func button(_ title:String,_ symbol:String,_ tag:Int,_ enabled:Bool=true) {
            let b=NSButton(image:NSImage(systemSymbolName:symbol,accessibilityDescription:Localizer.text(title))!,target:self,action:#selector(toolbarAction(_:)))
            b.bezelStyle = .regularSquare;b.isBordered=false;b.tag=tag;b.toolTip=Localizer.text(title);b.setAccessibilityLabel(Localizer.text(title));b.isEnabled=enabled
            b.contentTintColor = tag == tool.rawValue ? .systemBlue : (tag == -1 ? .systemRed : .labelColor)
            b.widthAnchor.constraint(equalToConstant:28).isActive=true;b.heightAnchor.constraint(equalToConstant:28).isActive=true
            stack.addArrangedSubview(b)
        }
        for choice in CaptureTool.allCases { button(choice.title,choice.symbol,choice.rawValue) }
        button("撤销","arrow.uturn.backward",200,!marks.isEmpty)
        button("重做","arrow.uturn.forward",201,!undone.isEmpty)
        button("长截图","rectangle.expand.vertical",CaptureAction.scroll.rawValue,marks.isEmpty)
        button("翻译","character.bubble",CaptureAction.translate.rawValue)
        button("保存原图…","square.and.arrow.down",CaptureAction.save.rawValue)
        button("取消","xmark",-1)
        button("复制截图","checkmark",CaptureAction.copy.rawValue)
        let container=NSVisualEffectView();container.material = .popover;container.state = .active
        container.wantsLayer=true;container.layer?.cornerRadius=8;container.layer?.backgroundColor=NSColor.white.withAlphaComponent(0.97).cgColor;container.appearance=NSAppearance(named:.aqua)
        container.toolTip=Localizer.text("在选区内滚动即可开始长截图")
        container.addSubview(stack)
        let size=stack.fittingSize;stack.frame=NSRect(origin:NSPoint(x:8,y:5),size:size)
        let width=min(bounds.width-16,size.width+16),height=size.height+10
        let below=selection.minY-height-8
        let vertical=below>=8 ? below : min(bounds.height-height-8,selection.maxY+8)
        container.frame=NSRect(x:max(8,min(selection.maxX-width,bounds.width-width-8)),y:max(8,vertical),width:width,height:height)
        addSubview(container);toolbar=container
        if tool != .selection { showColors(near:container.frame) }
    }
    private func showColors(near frame:NSRect) {
        let row=NSStackView();row.orientation = .horizontal;row.spacing=5
        for (i,color) in [NSColor.systemRed,.systemBlue,.systemGreen,.systemYellow,.white,.black].enumerated() {
            let b=NSButton(title:"●",target:self,action:#selector(colorAction(_:)));b.tag=i;b.isBordered=false;b.contentTintColor=color;b.font = .systemFont(ofSize:22);b.setAccessibilityLabel(Localizer.text("标注颜色")+" \(i+1)")
            row.addArrangedSubview(b)
        }
        for width in [2,4,7] {
            let b=NSButton(title:"\(width)",target:self,action:#selector(widthAction(_:)));b.tag=width;b.bezelStyle = .rounded;b.setAccessibilityLabel(Localizer.text("线条粗细")+" \(width)");row.addArrangedSubview(b)
        }
        let panel=NSVisualEffectView();panel.material = .popover;panel.state = .active;panel.appearance=NSAppearance(named:.aqua);panel.wantsLayer=true;panel.layer?.cornerRadius=8
        panel.addSubview(row);row.frame=NSRect(origin:NSPoint(x:8,y:5),size:row.fittingSize)
        let size=NSSize(width:row.fittingSize.width+16,height:row.fittingSize.height+10)
        panel.frame=NSRect(x:frame.minX,y:frame.minY-size.height-5>=8 ? frame.minY-size.height-5 : frame.maxY+5,width:size.width,height:size.height)
        if panel.frame.maxY>bounds.maxY-8 {panel.setFrameOrigin(NSPoint(x:frame.minX,y:bounds.maxY-size.height-8))}
        addSubview(panel);colorToolbar=panel
    }
    @objc private func colorAction(_ sender:NSButton) {markColor=[NSColor.systemRed,.systemBlue,.systemGreen,.systemYellow,.white,.black][sender.tag]}
    @objc private func widthAction(_ sender:NSButton) {markWidth=CGFloat(sender.tag)}
    @objc private func toolbarAction(_ sender:NSButton) {
        finishText()
        if let tool=CaptureTool(rawValue:sender.tag) {self.tool=tool;showToolbar();window?.invalidateCursorRects(for:self);return}
        if sender.tag==200 || sender.tag==201 {undoMark(redo:sender.tag==201);return}
        if sender.tag == -1 { cancelled?(); return }
        guard let action=CaptureAction(rawValue:sender.tag) else{return}
        confirm(action)
    }
}
