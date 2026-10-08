import AppKit

guard CommandLine.arguments.count == 2 else {
    print("BLOCKED · Supply the dedicated /bin/cat test session ID")
    exit(2)
}
let expectedSession = CommandLine.arguments[1]
func verifySession() {
    let verifier = NSAppleScript(source: "tell application \"iTerm2\" to get {id, name} of current session of current window")!
    var error: NSDictionary?
    let reply = verifier.executeAndReturnError(&error)
    guard error == nil, reply.atIndex(1)?.stringValue == expectedSession,
          reply.atIndex(2)?.stringValue == "cat" else {
        print("BLOCKED · Dedicated cat session not selected")
        exit(2)
    }
}
verifySession()
guard let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first,
      let inputMethod = NSRunningApplication.runningApplications(withBundleIdentifier: "app.guyi.inputmethod.Guyi").first else { exit(2) }
func frames() -> [CGRect] {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.compactMap { item in
        guard item[kCGWindowOwnerPID as String] as? Int32 == inputMethod.processIdentifier,
              item[kCGWindowLayer as String] as? Int == Int(NSWindow.Level.popUpMenu.rawValue),
              let bounds = item[kCGWindowBounds as String] as? [String: Any] else { return nil }
        return CGRect(dictionaryRepresentation: bounds as CFDictionary)
    }
}
guard frames().isEmpty else { print("BLOCKED · Existing GuYi candidate; preserve user composition"); exit(2) }
let codes: [Character: CGKeyCode] = ["a":0,"b":11,"c":8,"d":2,"e":14,"f":3,"g":5,"h":4,"i":34,"j":38,"k":40,"l":37,"m":46,"n":45,"o":31,"p":35,"q":12,"r":15,"s":1,"t":17,"u":32,"v":9,"w":13,"x":7,"y":16,"z":6]
for character in "woxiangceshiyixiazhegeshurufazaizhongwenshurushihoushifouhuidangzhuwodeshuruneirong" {
    verifySession()
    guard NSWorkspace.shared.frontmostApplication?.processIdentifier == terminal.processIdentifier else {
        print("BLOCKED · iTerm lost focus; stopped without Return or cleanup")
        exit(2)
    }
    let code = codes[character]!
    let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
    let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
    down?.flags = []
    up?.flags = []
    down?.postToPid(terminal.processIdentifier)
    up?.postToPid(terminal.processIdentifier)
    Thread.sleep(forTimeInterval: 0.10)
    print(frames().map { NSStringFromRect($0) }.joined(separator: ";"))
}
print("DONE · Test pinyin left uncommitted. No Return, paste, or shell command sent.")
