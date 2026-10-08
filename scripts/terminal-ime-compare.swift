import AppKit

let arguments = CommandLine.arguments
guard arguments.count == 4 else { exit(2) }
let sessionID = arguments[1]
let backendID = arguments[2]
let output = arguments[3]
guard let backend = NSRunningApplication.runningApplications(withBundleIdentifier: backendID).first else { exit(2) }
let verifier = NSAppleScript(source: "tell application \"iTerm2\" to get {id, name} of current session of current window")!
var verificationError: NSDictionary?
let initialSession = verifier.executeAndReturnError(&verificationError)
guard initialSession.atIndex(1)?.stringValue == sessionID,
      initialSession.atIndex(2)?.stringValue == "cat", verificationError == nil else { exit(2) }
let terminalPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first!.processIdentifier
let initialWindows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
let windowID = initialWindows.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == terminalPID && $0[kCGWindowLayer as String] as? Int == 0 })?[kCGWindowNumber as String] as? UInt32
guard windowID != nil else { exit(2) }
func verify() {
    verificationError = nil
    let session = verifier.executeAndReturnError(&verificationError)
    guard verificationError == nil, session.atIndex(1)?.stringValue == sessionID,
          session.atIndex(2)?.stringValue == "cat" else {
        print("BLOCKED · Dedicated cat session changed")
        exit(2)
    }
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    let currentWindowID = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == terminalPID && $0[kCGWindowLayer as String] as? Int == 0 })?[kCGWindowNumber as String] as? UInt32
    guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.googlecode.iterm2",
          currentWindowID == windowID else {
        print("BLOCKED · Dedicated cat terminal no longer focused")
        exit(2)
    }
}
let codes: [Character: CGKeyCode] = ["a":0,"b":11,"c":8,"d":2,"e":14,"f":3,"g":5,"h":4,"i":34,"j":38,"k":40,"l":37,"m":46,"n":45,"o":31,"p":35,"q":12,"r":15,"s":1,"t":17,"u":32,"v":9,"w":13,"x":7,"y":16,"z":6," ":49,"\n":36]
var frames: [CGRect] = []
func captureFrames() {
    let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
    for entry in windows where entry[kCGWindowOwnerPID as String] as? Int32 == backend.processIdentifier {
        guard let layer = entry[kCGWindowLayer as String] as? Int, layer > 0, layer < 1000,
              let bounds = entry[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary), rect.width > 80, rect.height > 20 else { continue }
        frames.append(rect)
    }
}
func type(_ text: String) {
    for character in text {
        verify()
        guard let code = codes[character] else { exit(2) }
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = []
            event.postToPid(terminalPID)
        }
        Thread.sleep(forTimeInterval: 0.06)
        captureFrames()
    }
}
Thread.sleep(forTimeInterval: 1)
type("nihao\nhello\nnihao  \n")
frames = []
type("woxiangceshiyixiazhegeshurufazaizhongwenshurushihoushifouhuidangzhuwodeshuruneirong")
Thread.sleep(forTimeInterval: 0.3)
verify()
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
if let terminal = NSRunningApplication.runningApplications(withBundleIdentifier: "com.googlecode.iterm2").first,
   let window = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int32 == terminal.processIdentifier && $0[kCGWindowLayer as String] as? Int == 0 }),
   let number = window[kCGWindowNumber as String] as? UInt32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-l\(number)", output + "-terminal.png"]
    try process.run()
    process.waitUntilExit()
}
if let frame = frames.last {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-R\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))", output + "-candidate.png"]
    try process.run()
    process.waitUntilExit()
}
print("SOURCE", backendID, "SAMPLES", frames.count)
print("HEIGHTS", Set(frames.map(\.height)).sorted())
if !frames.isEmpty {
    print("X_SPREAD", frames.map(\.minX).max()! - frames.map(\.minX).min()!)
    print("TOP_SPREAD", frames.map(\.minY).max()! - frames.map(\.minY).min()!)
    print("BOTTOM_SPREAD", frames.map(\.maxY).max()! - frames.map(\.maxY).min()!)
}
type("\n\n")
guard frames.count >= 10 else {
    print("FAIL · No valid candidate rendering evidence; source selection is not verified")
    exit(1)
}
print("DONE · All Return events confined to verified /bin/cat fixture")
