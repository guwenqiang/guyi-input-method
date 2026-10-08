import Carbon
import Foundation
import AppKit

if (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool == true {
    print("Unlock macOS before registering or enabling GuYi Input Method.")
    exit(2)
}
if CommandLine.arguments.contains("--preflight") {
    print("Desktop is unlocked; installation may proceed.")
    exit(0)
}

guard CommandLine.arguments.count == 2 else {
    print("Usage: RegisterGuYi --preflight | /path/to/GuYi.app")
    exit(2)
}
let path = CommandLine.arguments[1]
guard let bundle = Bundle(path: path), bundle.bundleIdentifier == "app.guyi.inputmethod.Guyi" else {
    print("Refusing to register a bundle that is not GuYi Input Method.")
    exit(1)
}
let modeContainer = bundle.object(forInfoDictionaryKey: "ComponentInputModeDict") as? [String: Any]
let modes = modeContainer?["tsInputModeListKey"] as? [String: Any] ?? [:]
let rootID = bundle.object(forInfoDictionaryKey: "TISInputSourceID") as? String ?? "app.guyi.inputmethod.Guyi"
let expectedIDs = Set(modes.keys).union([rootID])
func sourceID(_ source: TISInputSource) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
let status = TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL)
guard status == noErr else { print("Registration failed: \(status)"); exit(1) }
let filter = [kTISPropertyBundleID as String: "app.guyi.inputmethod.Guyi"] as CFDictionary
let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
guard !sources.isEmpty else { print("Registration returned no GuYi input sources."); exit(1) }
guard expectedIDs.isSubset(of: Set(sources.compactMap(sourceID))) else {
    print("Registration did not expose every input mode declared by this GuYi build.")
    exit(1)
}
for source in sources {
    guard let identifier = sourceID(source) else { continue }
    if !expectedIDs.contains(identifier) {
        let result = TISDisableInputSource(source)
        guard result == noErr else { print("Unable to disable obsolete GuYi input mode: \(result)"); exit(1) }
        print("Disabled obsolete GuYi input mode: \(identifier)")
    }
}
for identifier in [rootID] + modes.keys.sorted() {
    let refreshed = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    guard let source = refreshed.first(where: { sourceID($0) == identifier }) else {
        print("Input source disappeared during registration: \(identifier)")
        exit(1)
    }
    let result = TISEnableInputSource(source)
    guard result == noErr else { print("Enable input source failed: \(result)"); exit(1) }
    guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceIsEnabled),
          CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(pointer).takeUnretainedValue()) else {
        print("Input source remained disabled: \(identifier)")
        exit(1)
    }
    print("Enabled input source: \(identifier)")
}
print("Registered \(expectedIDs.count) declared input sources. This verifies registration only; select GuYi in a text field to verify activation.")
print("Confirm any macOS authorization prompt yourself. API success does not prove that the source is selectable in your working application.")
