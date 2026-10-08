import AppKit

guard CommandLine.arguments.count == 2 else { exit(2) }
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let deadline = Date().addingTimeInterval(90)
var processed = 0
var fixturePID: pid_t?
let allowedKeys: Set<CGKeyCode> = [45, 34, 4, 0, 31, 14, 37, 36, 49, 43, 39, 20, 47, 18, 21, 19, 23, 44, 24, 29, 69]
while Date() < deadline {
    let lines = ((try? String(contentsOf: output, encoding: .utf8)) ?? "").components(separatedBy: "\n")
    for line in lines.dropFirst(processed).dropLast() {
        processed += 1
        if line.hasPrefix("FAIL") || line.hasPrefix("BLOCKED") { exit(1) }
        if line.hasPrefix("PASS · Candidate anchor") { exit(0) }
        if line == "DIAGNOSTIC_DONE" { exit(0) }
        guard line.hasPrefix("TEST_KEY:") else { continue }
        let parts = line.split(separator: ":")
        guard parts.count == 3, let processID = Int32(parts[1]), let code = UInt16(parts[2]), allowedKeys.contains(code),
              fixturePID == nil || fixturePID == processID,
              NSRunningApplication(processIdentifier: processID)?.bundleIdentifier == "app.guyi.sandbox-input-fixture",
              NSWorkspace.shared.frontmostApplication?.processIdentifier == processID,
              (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true else {
            print("BLOCKED · Sandbox fixture lost focus or identity; no key posted")
            exit(2)
        }
        fixturePID = processID
        for down in [true, false] {
            CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)?.postToPid(processID)
        }
    }
    Thread.sleep(forTimeInterval: 0.01)
}
print("BLOCKED · Sandbox fixture timed out")
exit(2)
