import AppKit

@main
struct EditingSmoke {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        EditingMenu.install()
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        let field = NSSecureTextField(frame: NSRect(x: 20, y: 30, width: 260, height: 30))
        window.contentView?.addSubview(field)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(field)
        guard let editor = window.firstResponder as? NSTextView else { fatalError("No field editor") }
        editor.string = "GuYi shortcut test"
        let select = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                     windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        guard window.performKeyEquivalent(with: select),
              editor.selectedRange().length == editor.string.utf16.count else { fatalError("Command-A failed") }
        let editing = app.mainMenu!.items[1].submenu!
        guard editing.items.contains(where: { $0.keyEquivalent == "v" && $0.action == #selector(NSText.paste(_:)) && $0.target == nil }) else { fatalError("Missing responder-chain paste") }
        print("PASS · secure field Command-A and responder-chain Command-V binding")
        window.orderOut(nil)
    }
}
