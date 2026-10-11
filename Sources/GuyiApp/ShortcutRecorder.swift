import SwiftUI
import Carbon
import GuyiCore

struct ShortcutRecorder: NSViewRepresentable {
    @Binding var key: UInt32
    @Binding var modifiers: UInt32
    var allowsPlainKey = false
    func makeNSView(context: Context) -> ShortcutField { ShortcutField() }
    func updateNSView(_ field: ShortcutField, context: Context) {
        field.key = key
        field.modifiers = modifiers
        field.allowsPlainKey = allowsPlainKey
        field.changed = { code, flags in key = code; modifiers = flags }
        field.refreshTitle()
    }
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        return result
    }
}

final class ShortcutField: NSButton {
    var key: UInt32 = 21
    var modifiers: UInt32 = UInt32(cmdKey | controlKey)
    var changed: ((UInt32, UInt32) -> Void)?
    var allowsPlainKey = false
    private var recording = false
    private var monitor: Any?
    override var acceptsFirstResponder: Bool { true }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recording { return true }
        return super.performKeyEquivalent(with: event)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        bezelStyle = .rounded
        target = self
        action = #selector(beginRecording)
        setAccessibilityLabel("快捷键，点击后按下组合键")
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    @objc private func beginRecording() {
        guard !recording else { return }
        window?.makeFirstResponder(self)
        recording = true
        SelectionHotKey.shared.pauseRecording(true)
        title = Localizer.text("请按组合键 · Esc 取消")
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, self.recording, event.window === self.window else { return event }
            if event.keyCode == 53 { self.finish(); return nil }
            if event.keyCode == 48 && event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                self.finish()
                return event
            }
            let flags = ShortcutRecorder.carbonModifiers(event.modifierFlags)
            guard self.allowsPlainKey || flags & UInt32(cmdKey | optionKey | controlKey) != 0 else {
                self.title = Localizer.text("请包含 ⌘、⌥ 或 ⌃")
                return nil
            }
            self.key = UInt32(event.keyCode)
            self.modifiers = flags
            self.changed?(self.key, flags)
            self.finish()
            return nil
        }
    }
    private func finish() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        guard recording else { return }
        recording = false
        SelectionHotKey.shared.pauseRecording(false)
        refreshTitle()
    }
    override func resignFirstResponder() -> Bool { finish(); return super.resignFirstResponder() }
    override func viewWillMove(toWindow newWindow: NSWindow?) { if newWindow == nil { finish() }; super.viewWillMove(toWindow: newWindow) }
    func refreshTitle() {
        guard !recording else { return }
        guard key < 128 else { title = Localizer.text("未设置"); return }
        let symbols: [(UInt32, String)] = [(UInt32(controlKey), "⌃"), (UInt32(optionKey), "⌥"), (UInt32(shiftKey), "⇧"), (UInt32(cmdKey), "⌘")]
        let prefix = symbols.filter { modifiers & $0.0 != 0 }.map(\.1).joined()
        let names: [UInt32: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"-",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",39:"'",40:"K",41:";",42:"\\",43:",",44:"/",45:"N",46:"M",47:".",48:"⇥",49:"Space",50:"`",51:"⌫",96:"F5",97:"F6",98:"F7",99:"F3",100:"F8",101:"F9",103:"F11",109:"F10",111:"F12",118:"F4",120:"F2",122:"F1",123:"←",124:"→",125:"↓",126:"↑"]
        title = prefix + (names[key] ?? "Key \(key)")
    }
}
