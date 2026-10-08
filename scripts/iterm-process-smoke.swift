import AppKit
import Carbon

guard CommandLine.arguments.count >= 2, let processID = Int32(CommandLine.arguments[1]),
      NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == "com.googlecode.iterm2" else { exit(2) }
func code(_ value: String) -> UInt32 { value.utf8.reduce(0) { ($0 << 8) | UInt32($1) } }
let target = NSAppleEventDescriptor(processIdentifier: processID)
let create = NSAppleEventDescriptor(eventClass: code("Itrm"), eventID: code("nwwn"), targetDescriptor: target,
                                    returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
create.setParam(NSAppleEventDescriptor(string: "/bin/cat"), forKeyword: code("Nwcm"))
let created = try create.sendEvent(options: .waitForReply, timeout: 10)
guard created.paramDescriptor(forKeyword: keyErrorNumber)?.int32Value ?? 0 == 0 else { exit(2) }
NSRunningApplication(processIdentifier: processID)?.activate(options: [])
Thread.sleep(forTimeInterval: 0.5)
let application = AXUIElementCreateApplication(processID)
func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
    return result
}
guard let focused = attribute(application, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() else { exit(2) }
let window = focused as! AXUIElement
func verify() {
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
          let current = attribute(application, kAXFocusedWindowAttribute), CFEqual(current, window),
          (attribute(window, kAXTitleAttribute) as? String)?.lowercased().contains("cat") == true else {
        print("BLOCKED · Dedicated cat window changed")
        exit(2)
    }
}
func contents(_ element: AXUIElement, depth: Int = 0) -> String? {
    guard depth < 14 else { return nil }
    if attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole {
        return (attribute(element, kAXValueAttribute) as? String)?.replacingOccurrences(of: "\0", with: "")
    }
    for child in attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
        if let text = contents(child, depth: depth + 1) { return text }
    }
    return nil
}
verify()
guard !(contents(window) ?? "").contains("你好") else { exit(2) }
let keys: [Character: CGKeyCode] = ["n":45,"i":34,"h":4,"a":0,"o":31,"e":14,"l":37," ":49,"\n":36]
let rounds = CommandLine.arguments.contains("--switch-apps") ? 3 : 1
for round in 1...rounds {
    if rounds > 1 {
        NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate(options: [])
        Thread.sleep(forTimeInterval: 0.25)
        NSRunningApplication(processIdentifier: processID)?.activate(options: [])
        Thread.sleep(forTimeInterval: 0.25)
    }
    let before = (contents(window) ?? "").components(separatedBy: "你好").count
    for character in "nihao  \nhello\n\n" {
        verify()
        guard let key = keys[character] else { exit(2) }
        for down in [true, false] { CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: down)?.postToPid(processID) }
        Thread.sleep(forTimeInterval: 0.15)
    }
    let after = (contents(window) ?? "").components(separatedBy: "你好").count
    guard after > before else { print("FAIL · Chinese input after app switch", round); exit(1) }
    print("PASS · Chinese input round", round)
}
verify()
let result = contents(window) ?? ""
guard result.contains("你好"), result.contains("hello") else {
    print("FAIL · New iTerm did not commit both Chinese and raw English")
    exit(1)
}
print("PASS · New iTerm instance commits Chinese with Space and raw English with Return in a dedicated cat window")
