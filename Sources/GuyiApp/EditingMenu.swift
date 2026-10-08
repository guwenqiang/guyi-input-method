import AppKit
import GuyiCore

final class SettingsWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers == .command, let editor = firstResponder as? NSTextView {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": editor.selectAll(nil)
            case "c": editor.copy(nil)
            case "v": editor.paste(nil)
            case "x": editor.cut(nil)
            case "z": editor.undoManager?.undo()
            default: return super.performKeyEquivalent(with: event)
            }
            return true
        }
        if modifiers == [.command, .shift], event.charactersIgnoringModifiers?.lowercased() == "z",
           let editor = firstResponder as? NSTextView {
            editor.undoManager?.redo()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

enum EditingMenu {
    @MainActor static func install() {
        let main = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: Brand.name)
        applicationMenu.addItem(withTitle: Localizer.text("隐藏"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        applicationItem.submenu = applicationMenu
        main.addItem(applicationItem)
        let editingItem = NSMenuItem()
        let editing = NSMenu(title: Localizer.text("编辑"))
        editing.addItem(withTitle: Localizer.text("撤销"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editing.addItem(withTitle: Localizer.text("重做"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editing.addItem(.separator())
        editing.addItem(withTitle: Localizer.text("剪切"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editing.addItem(withTitle: Localizer.text("复制"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editing.addItem(withTitle: Localizer.text("粘贴"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editing.addItem(withTitle: Localizer.text("全选"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editingItem.submenu = editing
        main.addItem(editingItem)
        NSApp.mainMenu = main
    }
}
