import Carbon
import Foundation

func property(_ source: TISInputSource, _ key: CFString) -> String {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return "" }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}
let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
if CommandLine.arguments.count == 1 {
    print(property(current, kTISPropertyInputSourceID))
} else {
    let sourceID = CommandLine.arguments[1]
    let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
    guard let source = sources.first(where: { property($0, kTISPropertyInputSourceID) == sourceID }) else { print("Source not found: " + sourceID); exit(1) }
    let status = TISSelectInputSource(source)
    print("Select \(sourceID): \(status)")
    if status != noErr { exit(1) }
}
