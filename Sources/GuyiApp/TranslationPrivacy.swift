import AppKit
import Carbon
import GuyiCore

enum TranslationPrivacy {
    private static let queue = DispatchQueue(label: "app.guyi.private-context", qos: .userInitiated)
    static func protectedContext() -> Bool {
        if IsSecureEventInputEnabled() { return true }
        guard let front = NSWorkspace.shared.frontmostApplication else { return true }
        return SensitiveContentPolicy.protectedApplication(front.bundleIdentifier)
    }
    @MainActor static func excludedFocusedField(pid: pid_t) async -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.05)
        var systemFocus: CFTypeRef?
        if AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &systemFocus) == .success,
           let systemFocus, CFGetTypeID(systemFocus) == AXUIElementGetTypeID() {
            var owner: pid_t = 0
            let element = systemFocus as! AXUIElement
            if AXUIElementGetPid(element, &owner) == .success, owner == pid {
                return excluded(element)
            }
        }
        return await withCheckedContinuation { continuation in
            queue.async { continuation.resume(returning: readExcludedFocus(pid: pid)) }
        }
    }
    private static func readExcludedFocus(pid: pid_t) -> Bool {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        return excluded(focused as! AXUIElement)
    }
    private static func excluded(_ element: AXUIElement) -> Bool {
        var role: CFTypeRef?, subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if ["AXTextField", "AXComboBox", "AXSearchField"].contains(role as? String ?? "") { return true }
        return ["AXSecureTextField", "AXSearchField"].contains(subrole as? String ?? "")
    }
    static func protectedClipboard(_ pasteboard: NSPasteboard) -> Bool {
        let types = (pasteboard.types ?? []).map(\.rawValue)
        // Only source metadata, never the clipboard string, is read here.
        let source = pasteboard.string(forType: .init("org.nspasteboard.source"))
        return SensitiveContentPolicy.blocksClipboard(types: types, source: source,
            foreground: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
    }
}
