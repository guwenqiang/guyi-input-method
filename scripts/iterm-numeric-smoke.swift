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
let keys: [Character: CGKeyCode] = ["0":29,"1":18,"2":19,"3":20,"4":21,"5":23,"6":22,"7":26,"8":28,"9":25,".":47,",":43,"/":44,"=":24,"+":69,"-":27," ":49,"\n":36]
func type(_ value:String) {
 for c in value {
  verify()
  guard let key=keys[c] else{exit(2)}
  for down in [true,false] {let e=CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:down);e?.flags=[];e?.postToPid(processID)}
  Thread.sleep(forTimeInterval:0.16)
 }
}
let menu=Process()
menu.executableURL=URL(fileURLWithPath:"/usr/bin/swift")
menu.arguments=["scripts/select-input-source.swift"]
try menu.run();menu.waitUntilExit()
guard menu.terminationStatus==0 else{print("BLOCKED · Input menu selection failed");exit(2)}
Thread.sleep(forTimeInterval:0.3)
for sample in ["1.2", "0.2.27", "192.168.1.1", "3,444", "3,444.50", "09:30"] {
 if sample.contains(":"){continue}
 type(sample+" ")
 guard (contents(window) ?? "").contains(sample) else{print("FAIL · Terminal numeric punctuation",sample);exit(1)}
 print("PASS · Terminal numeric punctuation",sample)
}
type("\n")
for (expression,result) in [("5/5=","1"),("1/3=","1/3"),("0.1+0.2=","0.3"),("3,444+1=","3,445")] {
 type(expression)
 Thread.sleep(forTimeInterval:0.3)
 type("\n")
 // A suffix on the same line proves Return inserted the result without a newline.
 type("9")
 guard (contents(window) ?? "").contains(expression+result+"9") else{print("FAIL · Calculator or Return newline",expression);exit(1)}
 print("PASS · Terminal exact result and no Return newline",expression+result)
 type(" \n")
}
print("PASS · Dedicated cat numeric and calculator acceptance")
