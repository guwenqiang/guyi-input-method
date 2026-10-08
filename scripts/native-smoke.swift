import AppKit
import Carbon

final class NativeSmoke: NSObject, NSApplicationDelegate {
    let window = NSWindow(contentRect: NSRect(x: 180, y: 180, width: 760, height: 360), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let editor = NSTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 360))
    var previous: TISInputSource?
    var failures = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        previous = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        editor.font = .systemFont(ofSize: 22)
        editor.isRichText = false
        window.title = "GuYi · 自动化原生输入测试"
        window.contentView = editor
        window.center()
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editor)
        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        if CommandLine.arguments.contains("--manual") { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
            for source in sources {
                if let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
                   Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String == "app.guyi.inputmethod.Guyi.pinyin" {
                    print("Select: \(TISSelectInputSource(source))")
                }
            }
            editor.inputContext?.activate()
            print("Input context: \(editor.inputContext?.selectedKeyboardInputSource ?? "none")")
            try? await Task.sleep(nanoseconds: 600_000_000)
            await type("nihao")
            await key(49, " ")
            check(editor.string == "你好", "Space selects and commits 你好 without Return")
            check(!editor.hasMarkedText(), "Composition committed")
            await key(29, "0", flags: .option)
            await type("Good morning")
            await key(36, "\r")
            check(editor.string == "你好Good morning", "English mode, spaces preserved")
            await key(29, "0", flags: .option)
            await type("Selamat pagi")
            await key(36, "\r")
            check(editor.string == "你好Good morningSelamat pagi", "Indonesian mode")
            await type("cancel")
            await key(53, "\u{1b}")
            check(editor.string == "你好Good morningSelamat pagi", "Escape clears only composition")
            if let previous { _ = TISSelectInputSource(previous) }
            print("Native input checks: \(failures == 0 ? "PASS" : "FAIL")")
            fflush(stdout)
            exit(failures == 0 ? 0 : 1)
        }
    }
    func check(_ condition: Bool, _ name: String) {
        print("\(condition ? "PASS" : "FAIL") · \(name) · actual=\(editor.string.debugDescription)")
        if !condition { failures += 1 }
    }
    @MainActor func type(_ text: String) async {
        let codes: [Character: UInt16] = ["n":45,"i":34,"h":4,"a":0,"o":31,"g":5,"d":2,"m":46,"r":15,"s":1,"e":14,"l":37,"t":17,"p":35,"c":8," ":49]
        for character in text {
            let lower = Character(String(character).lowercased())
            await key(codes[lower] ?? 0, String(character), flags: character.isUppercase ? .shift : [])
        }
    }
    @MainActor func key(_ code: UInt16, _ text: String, flags: NSEvent.ModifierFlags = []) async {
        guard NSApp.isActive else { print("Test stopped: dedicated window lost focus"); exit(2) }
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                    windowNumber: window.windowNumber, context: nil, characters: text,
                                    charactersIgnoringModifiers: text, isARepeat: false, keyCode: code)!
        window.sendEvent(event)
        try? await Task.sleep(nanoseconds: 120_000_000)
    }
}

let application = NSApplication.shared
let delegate = NativeSmoke()
application.setActivationPolicy(.regular)
application.delegate = delegate
application.run()
