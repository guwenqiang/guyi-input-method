import AppKit
let name=CommandLine.arguments.dropFirst().first ?? "GuYi输入法"
guard let app=NSRunningApplication.runningApplications(withBundleIdentifier:"com.apple.TextInputMenuAgent").first else {print("BLOCKED · Input menu unavailable");exit(2)}
func attr(_ e:AXUIElement,_ key:String)->CFTypeRef?{var v:CFTypeRef?;guard AXUIElementCopyAttributeValue(e,key as CFString,&v) == .success else{return nil};return v}
let root=AXUIElementCreateApplication(app.processIdentifier)
var bar:AXUIElement?
if let value=attr(root,"AXExtrasMenuBar"),CFGetTypeID(value)==AXUIElementGetTypeID(){bar=(value as! AXUIElement)}
if bar==nil {bar=(attr(root,kAXChildrenAttribute) as? [AXUIElement])?.last(where:{attr($0,kAXRoleAttribute) as? String == "AXMenuBar"})}
guard let bar,let item=(attr(bar,kAXChildrenAttribute) as? [AXUIElement])?.first else{print("BLOCKED · Input menu bar unavailable");exit(2)}
var menu=(attr(item,kAXChildrenAttribute) as? [AXUIElement])?.first(where:{attr($0,kAXRoleAttribute) as? String == "AXMenu"})
if menu == nil {
    guard AXUIElementPerformAction(item,kAXPressAction as CFString) == .success else {print("BLOCKED · Cannot open input menu");exit(2)}
    for _ in 0..<20 {
        Thread.sleep(forTimeInterval:0.05)
        menu=(attr(item,kAXChildrenAttribute) as? [AXUIElement])?.first(where:{attr($0,kAXRoleAttribute) as? String == "AXMenu"})
        if menu != nil {break}
    }
}
guard let menu else {print("BLOCKED · Input menu did not open");exit(2)}
var items=[AXUIElement]()
for _ in 0..<40 {
    items=attr(menu,kAXChildrenAttribute) as? [AXUIElement] ?? []
    if items.contains(where:{attr($0,kAXTitleAttribute) as? String == name}) {break}
    Thread.sleep(forTimeInterval:0.05)
}
if CommandLine.arguments.contains("--inspect") { for i in items {print(attr(i,kAXTitleAttribute) as? String ?? "",attr(i,kAXEnabledAttribute) ?? "")} }
guard let source=items.first(where:{attr($0,kAXTitleAttribute) as? String == name}),attr(source,kAXEnabledAttribute) as? Bool == true else {
 _=AXUIElementPerformAction(menu,"AXCancel" as CFString);print("BLOCKED · Source not selectable",name);exit(2)
}
let result=AXUIElementPerformAction(source,kAXPressAction as CFString)
print("Selected system menu source",name,"status",result.rawValue)
exit(result == .success ? 0:2)
