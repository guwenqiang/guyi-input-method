import AppKit

guard CommandLine.arguments.count == 2, let processID = Int32(CommandLine.arguments[1]),
      NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == "com.apple.Terminal" else { exit(2) }
let application = AXUIElementCreateApplication(processID)
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}
func focusedWindow() -> AXUIElement {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
          let value = attribute(application, kAXFocusedWindowAttribute),
          CFGetTypeID(value) == AXUIElementGetTypeID() else { exit(2) }
    let window = value as! AXUIElement
    guard (attribute(window, kAXTitleAttribute) as? String)?.contains("terminal-fixture.command") == true else { exit(2) }
    return window
}
func text(in element: AXUIElement, depth: Int = 0) -> String? {
    guard depth < 12 else { return nil }
    if attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole {
        return attribute(element, kAXValueAttribute) as? String
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let value = text(in: child, depth: depth + 1) { return value }
    }
    return nil
}
let initial = text(in: focusedWindow()) ?? ""
guard !initial.contains("你好"), !initial.contains("hello") else { exit(2) }
let keys: [Character: CGKeyCode] = ["n": 45, "i": 34, "h": 4, "a": 0, "o": 31, "e": 14, "l": 37, " ": 49, "\n": 36]
func type(_ value: String) {
    for character in value {
        _ = focusedWindow()
        guard let key = keys[character] else { exit(2) }
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)?.postToPid(processID)
        }
        Thread.sleep(forTimeInterval: 0.12)
    }
}
type("nihao  \nhello\n\n")
Thread.sleep(forTimeInterval: 0.3)
guard let result = text(in: focusedWindow()), result.contains("你好"), result.contains("hello") else {
    print("FAIL · Real Terminal did not commit Chinese and raw English")
    exit(1)
}
print("PASS · Real Terminal commits Chinese with Space and raw English with Return")
