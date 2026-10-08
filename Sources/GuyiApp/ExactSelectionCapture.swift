import AppKit
import Carbon
import GuyiCore

@MainActor
enum ExactSelectionCapture {
    private struct Snapshot {
        let items: [NSPasteboardItem]

        init?(_ pasteboard: NSPasteboard) {
            let originals: [NSPasteboardItem]
            if let items = pasteboard.pasteboardItems { originals = items }
            else if pasteboard.types?.isEmpty != false { originals = [] }
            else { return nil }
            var copies: [NSPasteboardItem] = []
            var bytes = 0
            for item in originals {
                let copy = NSPasteboardItem()
                for type in item.types {
                    guard !type.rawValue.localizedCaseInsensitiveContains("promise"),
                          let data = item.data(forType: type), bytes + data.count <= 64 * 1_024 * 1_024,
                          copy.setData(data, forType: type) else { return nil }
                    bytes += data.count
                }
                copies.append(copy)
            }
            items = copies
        }

        func restore(_ pasteboard: NSPasteboard, ifUnchanged count: Int) -> Bool {
            guard pasteboard.changeCount == count else { return false }
            pasteboard.clearContents()
            guard items.isEmpty || pasteboard.writeObjects(items) else { return false }
            let restored = pasteboard.pasteboardItems ?? []
            guard restored.count == items.count else { return false }
            return zip(items, restored).allSatisfy { original, current in
                original.types == current.types && original.types.allSatisfy {
                    original.data(forType: $0) == current.data(forType: $0)
                }
            }
        }
    }

    static func read(pid: pid_t, mouseCount: UInt64, currentMouseCount: () -> UInt64) async -> String? {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              !IsSecureEventInputEnabled() else { return nil }
        let pasteboard = NSPasteboard.general
        guard !TranslationPrivacy.protectedClipboard(pasteboard),
              let snapshot = Snapshot(pasteboard) else { return nil }
        let before = pasteboard.changeCount
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 8, keyDown: false) else { return nil }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)

        for _ in 0..<15 where pasteboard.changeCount == before {
            try? await Task.sleep(for: .milliseconds(20))
        }
        guard pasteboard.changeCount != before else { return nil }
        try? await Task.sleep(for: .milliseconds(35))
        let copiedCount = pasteboard.changeCount
        let text = pasteboard.string(forType: .string)
        let restored = snapshot.restore(pasteboard, ifUnchanged: copiedCount)
        guard restored, NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              currentMouseCount() == mouseCount,
              let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.count <= 4_000, !SensitiveContentPolicy.resemblesSecret(text) else { return nil }
        return text
    }
}
