import AppKit
import Carbon
import SwiftUI
import GuyiCore
import ScreenCaptureKit
import UniformTypeIdentifiers

@MainActor
final class ScreenshotService: ObservableObject {
    static let shared = ScreenshotService()
    @Published private(set) var status = ""
    @Published private(set) var capturing = false
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var overlay: CaptureOverlay?
    private var captureRect: CGRect?
    private var previousFrame: CGImage?
    private var combinedFrame: CGImage?
    private var enabled = false
    private var resultWindow: NSWindow?
    private var configuredKey: UInt32 = 21
    private var configuredModifiers: UInt32 = 4352
    private var recordingShortcut = false
    private var scrollTask: Task<Void, Never>?
    private var scrollPanel: NSPanel?
    private var scrollBorder: NSPanel?
    private var scrollCapture: ScrollRegionCapture?
    private var scrollTopFrame: CGImage?
    private var scrollBottomFrame: CGImage?
    private var finishingScroll = false
    private var scrollSteps = ScrollStepQueue()
    private var scrollEventGate: ScrollEventGate?
    private var forwardingScroll = false
    private var cancelPendingScroll = false
    private var restoreAfterScroll = true
    private let inlineTranslation = InlineScreenshotTranslation()
    private var captureOwner: NSRunningApplication?
    private var captureWindowID: CGWindowID?

    private init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { ScreenshotService.shared.capture() }
            return noErr
        }, 1, &type, nil, &handler)
    }
    func configure(enabled: Bool, key: UInt32, modifiers: UInt32) {
        self.enabled = enabled
        configuredKey = key
        configuredModifiers = modifiers
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard enabled, !recordingShortcut else { status = enabled ? "" : "已关闭"; return }
        guard modifiers != 0 else { status = "请选择组合键"; return }
        guard !(modifiers & UInt32(cmdKey | shiftKey) == UInt32(cmdKey | shiftKey) && [20, 21, 23, 22].contains(key)) else {
            status = "此组合由 macOS 截图占用，请使用 ⌃⌘4 或其他组合"
            return
        }
        let result = RegisterEventHotKey(key, modifiers, EventHotKeyID(signature: 0x47555949, id: 1), GetApplicationEventTarget(), 0, &hotKey)
        status = result == noErr ? "" : "快捷键不可用，请更换组合"
    }
    func pauseShortcutRecording(_ paused: Bool) {
        recordingShortcut = paused
        configure(enabled: enabled, key: configuredKey, modifiers: configuredModifiers)
    }
    func capture() {
        guard enabled, !capturing, !recordingShortcut else { return }
        if !CGPreflightScreenCaptureAccess() {
            _ = CGRequestScreenCaptureAccess()
            status = "请在系统设置中允许屏幕录制，然后重试"
            let alert = NSAlert()
            alert.messageText = Localizer.text("需要屏幕录制权限")
            alert.informativeText = Localizer.format("请在系统设置的屏幕录制权限中允许%@。更新后可能需要重新授权并重启输入法。", Brand.name)
            alert.addButton(withTitle: Localizer.text("打开系统设置"))
            alert.addButton(withTitle: Localizer.text("取消"))
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
            return
        }
        capturing = true
        status = "框选截图，Esc 取消"
        captureOwner = NSWorkspace.shared.frontmostApplication
        AppDelegate.shared.prepareForScreenshot()
        inlineTranslation.close()
        resultWindow?.close()
        resultWindow = nil
        previousFrame = nil
        combinedFrame = nil
        let overlay = CaptureOverlay()
        self.overlay = overlay
        overlay.cancelled = { [weak self] in self?.capturing = false; self?.overlay = nil }
        Task {
            do {
                try await Task.sleep(for: .milliseconds(200))
                try await overlay.start { [weak self] image, rect, action, firstScroll, target in
                    guard let self else { return }
                    self.capturing = false
                    self.overlay = nil
                    self.captureRect = rect
                    self.captureOwner = target.flatMap { NSRunningApplication(processIdentifier: $0.0) }
                    self.captureWindowID = target?.1
                    self.previousFrame = image
                    self.combinedFrame = image
                    switch action {
                    case .translate: self.inlineTranslation.show(image: image, rect: rect)
                    case .scroll: self.scrollNext(firstScroll: firstScroll)
                    case .save: self.save(image)
                    case .copy:
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
                        self.combinedFrame = nil
                        self.previousFrame = nil
                    }
                }
            } catch { self.capturing = false; self.overlay = nil; self.status = "无法截图：\(error.localizedDescription)" }
        }
    }
    private func save(_ image: CGImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "GuYi-Screenshot.png"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            do {
                guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { throw ScrollCapture.Failure.limit }
                try data.write(to: url, options: .atomic)
                self?.combinedFrame = nil
                self?.previousFrame = nil
            } catch { NSAlert(error: error).runModal() }
        }
    }
    private func captureWindowIsVisible() -> Bool {
        guard let rect = captureRect, let expected = captureWindowID, let owner = captureOwner else { return false }
        let point = CGPoint(x: rect.midX, y: rect.midY)
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for entry in windows {
            guard entry[kCGWindowOwnerPID as String] as? Int32 != getpid(),
                  entry[kCGWindowLayer as String] as? Int == 0,
                  let values = entry[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: values as CFDictionary), bounds.contains(point) else { continue }
            return entry[kCGWindowOwnerPID as String] as? Int32 == owner.processIdentifier && entry[kCGWindowNumber as String] as? UInt32 == expected
        }
        return false
    }
    private func present(_ image: CGImage) {
        let bitmap = NSBitmapImageRep(cgImage: image)
        guard let data = bitmap.representation(using: .png, properties: [:]) else { return }
        showTranslation(image: NSImage(cgImage: image, size: .zero), data: data)
    }
    private func scrollNext(firstScroll: CGEvent? = nil) {
        guard !capturing, let rect=captureRect, let previous=previousFrame, let combined=combinedFrame,
              let owner=captureOwner, !owner.isTerminated else { return }
        capturing=true;finishingScroll=false;cancelPendingScroll=false;restoreAfterScroll=true;scrollSteps.clear();resultWindow?.orderOut(nil)
        scrollTopFrame=combined.cropping(to:CGRect(x:0,y:0,width:previous.width,height:previous.height)) ?? previous
        scrollBottomFrame=combined.cropping(to:CGRect(x:0,y:combined.height-previous.height,width:previous.width,height:previous.height)) ?? previous
        let mainHeight=NSScreen.screens.first?.frame.maxY ?? 0
        let selectionFrame=NSRect(x:rect.minX,y:mainHeight-rect.maxY,width:rect.width,height:rect.height)
        let screen=NSScreen.screens.first(where:{$0.frame.intersects(selectionFrame)}) ?? NSScreen.main!
        let visible=screen.visibleFrame
        let border=ScrollInteractionPanel(contentRect:screen.frame,styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        border.backgroundColor = .clear;border.isOpaque=false;border.hasShadow=false;border.hidesOnDeactivate=false;border.isReleasedWhenClosed=false;border.level = .statusBar
        let interaction=ScrollInteractionView(frame:NSRect(origin:.zero,size:screen.frame.size),selection:selectionFrame.offsetBy(dx:-screen.frame.minX,dy:-screen.frame.minY),targetPID:owner.processIdentifier)
        interaction.scroll = { [weak self] event in
            guard let self, !self.finishingScroll else { return }
            self.scrollSteps.add(Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 10))
        }
        interaction.finish={ [weak self] in self?.finishScroll(cancel:false,save:true) }
        interaction.cancel={ [weak self] in self?.finishScroll(cancel:true) }
        border.contentView=interaction;border.makeKeyAndOrderFront(nil);border.makeFirstResponder(interaction);scrollBorder=border
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:430,height:78),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .popUpMenu;panel.isReleasedWhenClosed=false;panel.hidesOnDeactivate=false;panel.isOpaque=false;panel.backgroundColor = .clear
        panel.contentView=NSHostingView(rootView:ScrollCaptureControls(service:self,cancel:{ [weak self] in self?.finishScroll(cancel:true) },save:{ [weak self] in self?.finishScroll(cancel:false,save:true) },preview:{ [weak self] in self?.finishScroll(cancel:false) }))
        let below=selectionFrame.minY-panel.frame.height-8
        panel.setFrameOrigin(NSPoint(x:max(visible.minX+8,min(selectionFrame.maxX-panel.frame.width,visible.maxX-panel.frame.width-8)),y:max(visible.minY+8,min(below>=visible.minY+8 ? below : selectionFrame.maxY+8,visible.maxY-panel.frame.height-8))))
        panel.orderFrontRegardless();scrollPanel=panel
        let gate = ScrollEventGate()
        gate.consume = { [weak self] type, event in
            guard let self, self.capturing, self.captureWindowIsVisible(), rect.contains(event.location) else { return false }
            if type == .scrollWheel {
                if !self.finishingScroll, let wheel = NSEvent(cgEvent: event) {
                    self.scrollSteps.add(Double(wheel.scrollingDeltaY) * (wheel.hasPreciseScrollingDeltas ? 1 : 10))
                }
                return true
            }
            if self.forwardingScroll {
                if type == .leftMouseDown, event.getIntegerValueField(.mouseEventClickState) == 2 {
                    self.finishScroll(cancel: false, save: true)
                }
                return true
            }
            return false
        }
        if gate.start() { scrollEventGate = gate }
        status=Localizer.text("在选区内滚动 · 双击或保存结束")
        if let firstScroll, let event = NSEvent(cgEvent: firstScroll) {
            scrollSteps.add(Double(event.scrollingDeltaY) * (event.hasPreciseScrollingDeltas ? 1 : 10))
        }
        scrollTask=Task {
            do {
                let capture=try await ScrollRegionCapture.prepare(rect:rect,pixelSize:CGSize(width:previous.width,height:previous.height))
                guard !Task.isCancelled else{return}
                guard self.captureWindowIsVisible() else { throw ScrollCapture.Failure.mismatch }
                // Capture after the selection overlay has closed, before releasing
                // queued wheel events. This baseline matches the live window state.
                let baseline = try await capture.capture()
                guard !Task.isCancelled else { return }
                self.scrollCapture = capture
                self.previousFrame = baseline; self.combinedFrame = baseline
                self.scrollTopFrame = baseline; self.scrollBottomFrame = baseline
                await sampleScroll(capture)
            } catch {if !Task.isCancelled {status=Localizer.text("无法开始捕获，请取消后重试")}}
        }
    }
    private func sampleScroll(_ capture: ScrollRegionCapture) async {
        while !Task.isCancelled && !cancelPendingScroll {
            do {
                if let step = scrollSteps.take(viewportHeight: Double(captureRect?.height ?? 300)),
                   captureOwner != nil, let rect = captureRect {
                    let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: step, wheel2: 0, wheel3: 0)
                    event?.location = CGPoint(x: rect.midX, y: rect.midY)
                    guard captureWindowIsVisible() else { throw ScrollCapture.Failure.mismatch }
                    forwardingScroll = true
                    scrollBorder?.ignoresMouseEvents = true
                    // Posting directly to a PID leaves scroll events without a
                    // native window target. Let WindowServer route the tagged
                    // event while the capture panel temporarily ignores hits.
                    try await Task.sleep(for: .milliseconds(25))
                    event?.setIntegerValueField(.eventSourceUserData, value: ScrollEventGate.forwardedTag)
                    guard captureWindowIsVisible() else { throw ScrollCapture.Failure.mismatch }
                    event?.post(tap: .cghidEventTap)
                    try await Task.sleep(for: .milliseconds(25))
                    scrollBorder?.ignoresMouseEvents = false
                    forwardingScroll = false
                    try await Task.sleep(for: .milliseconds(180))
                } else {
                    if finishingScroll { break }
                    try await Task.sleep(for: .milliseconds(180))
                }
                guard captureWindowIsVisible() else { throw ScrollCapture.Failure.mismatch }
                var first = try await capture.capture()
                var stable: CGImage?
                for _ in 0..<8 {
                    try await Task.sleep(for: .milliseconds(100))
                    let next = try await capture.capture()
                    if ScrollCapture.isStable(first, next) { stable = next; break }
                    first = next
                }
                try Task.checkCancellation()
                guard let stable else { throw ScrollCapture.Failure.mismatch }
                try await consumeScrollFrame(stable)
            } catch is CancellationError {
                scrollBorder?.ignoresMouseEvents = false; forwardingScroll = false
                break
            }
            catch {
                scrollBorder?.ignoresMouseEvents = false; forwardingScroll = false
                // Stop advancing after a failed overlap so a later event cannot
                // skip yet another uncaptured section. Saving still validates tail.
                scrollSteps.clear()
                status = error.localizedDescription
                if finishingScroll { break }
            }
        }
    }
    private func consumeScrollFrame(_ next:CGImage) async throws {
        guard let top=scrollTopFrame,let bottom=scrollBottomFrame,let combined=combinedFrame else{return}
        let update=try await Task.detached { () -> (CGImage,Bool)? in
            if ScrollCapture.contains(next,in:combined){return nil}
            do{return (try ScrollCapture.append(previous:bottom,next:next,combined:combined),false)}
            catch ScrollCapture.Failure.mismatch{return (try ScrollCapture.prepend(previous:top,next:next,combined:combined),true)}
        }.value
        try Task.checkCancellation()
        if let update {
            if update.1{scrollTopFrame=next}else{scrollBottomFrame=next}
            previousFrame=next;combinedFrame=update.0
        }
        let height=combinedFrame?.height ?? next.height
        status=Localizer.text("长截图")+" · \(next.width) × \(height) px · "+Localizer.text("双击或保存结束")
    }
    func hostDidChange() {
        guard capturing, scrollBorder != nil, let front = NSWorkspace.shared.frontmostApplication,
              front.processIdentifier != getpid(), front.processIdentifier != captureOwner?.processIdentifier else { return }
        finishScroll(cancel: true, restoreFocus: false)
    }
    private func finishScroll(cancel:Bool,save:Bool=false,restoreFocus:Bool=true) {
        if cancel {
            cancelPendingScroll = true
            restoreAfterScroll = restoreFocus
            scrollSteps.clear()
        }
        guard !finishingScroll else { return }
        finishingScroll=true
        let pending=scrollTask
        if cancel { pending?.cancel(); scrollSteps.clear() }
        scrollTask=nil
        Task {
            await pending?.value
            var shouldCancel = cancel || self.cancelPendingScroll
            if !shouldCancel, scrollCapture == nil {
                finishingScroll = false
                status = Localizer.text("无法开始捕获，请取消后重试")
                return
            }
            if !shouldCancel,let capture=scrollCapture {
                do {
                    guard self.captureWindowIsVisible() else { throw ScrollCapture.Failure.mismatch }
                    let first=try await capture.capture()
                    try await Task.sleep(for:.milliseconds(160))
                    let next=try await capture.capture()
                    guard ScrollCapture.isStable(first,next) else{throw ScrollCapture.Failure.mismatch}
                    try await consumeScrollFrame(next)
                } catch {
                    // Never silently save an unverified tail as a complete long image.
                    if !cancelPendingScroll {
                        status=Localizer.text("末段未能拼接，请取消或返回已捕获区域后重试")
                        finishingScroll=false
                        scrollTask=Task { await self.sampleScroll(capture) }
                        return
                    }
                }
            }
            shouldCancel = shouldCancel || cancelPendingScroll
            scrollEventGate?.stop(); scrollEventGate = nil; forwardingScroll = false
            scrollPanel?.close();scrollPanel=nil;scrollBorder?.close();scrollBorder=nil
            scrollCapture=nil;scrollTopFrame=nil;scrollBottomFrame=nil;capturing=false;finishingScroll=false
            if shouldCancel {
                combinedFrame=nil;previousFrame=nil;captureRect=nil;status=Localizer.text("已取消");if restoreAfterScroll {captureOwner?.activate(options:[])}
            } else if let image=combinedFrame {
                if save {self.save(image)} else {present(image)}
            }
        }
    }
    private func showTranslation(image: NSImage, data: Data) {
        resultWindow?.close()
        let model = ScreenshotTranslation(image: image, data: data)
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 660),
                                    styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = Localizer.text("截图翻译")
        window.level = .normal
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.contentView = NSHostingView(rootView: ScreenshotTranslationView(model: model, scrollNext: { [weak self] in self?.scrollNext() }, close: { [weak self, weak window] in
            window?.close()
            self?.previousFrame = nil
            self?.combinedFrame = nil
            self?.captureRect = nil
        }))
        window.center()
        resultWindow = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct ScrollCaptureControls: View {
    @ObservedObject var service:ScreenshotService
    let cancel:()->Void
    let save:()->Void
    let preview:()->Void
    var body:some View {
        VStack(spacing:8){
            Text(service.status).font(.caption).lineLimit(2)
            HStack{
                Button(Localizer.text("取消"),action:cancel)
                Spacer()
                Button(Localizer.text("预览长截图"),action:preview)
                Button(Localizer.text("保存长截图…"),action:save).buttonStyle(.borderedProminent)
            }
        }.padding(10).background(.regularMaterial,in:RoundedRectangle(cornerRadius:8))
    }
}
