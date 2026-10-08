import AppKit

guard let target = NSRunningApplication.runningApplications(withBundleIdentifier: "app.guyi.inputmethod.Guyi").first else { exit(2) }
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
guard windows.contains(where: { ($0[kCGWindowOwnerPID as String] as? Int32) == target.processIdentifier && ($0[kCGWindowLayer as String] as? Int) == Int(NSWindow.Level.screenSaver.rawValue) }) else {
    print("BLOCKED · No GuYi capture overlay")
    exit(2)
}
let source = CGEventSource(stateID: .hidSystemState)
func post(_ kind: CGEventType, _ point: CGPoint) {
    guard let event = CGEvent(mouseEventSource: source, mouseType: kind, mouseCursorPosition: point, mouseButton: .left) else { exit(2) }
    event.flags = []
    event.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.06)
}
post(.mouseMoved, CGPoint(x: 205, y: 282))
post(.leftMouseDown, CGPoint(x: 205, y: 282))
for step in 1...20 { post(.leftMouseDragged, CGPoint(x: 205 + step * 35, y: 282 + step * 21)) }
post(.leftMouseUp, CGPoint(x: 905, y: 702))
print("Drag delivered within synthetic fixture")
