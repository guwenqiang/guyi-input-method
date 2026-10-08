import Carbon
import Foundation
import AppKit

if (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool == true {
    print("BLOCKED · Screen is locked; input-source availability is not a valid desktop acceptance result")
    exit(2)
}
print("SECURE_INPUT", IsSecureEventInputEnabled())
if IsSecureEventInputEnabled() {
    print("NOTE · Secure Input is active; this is normal in password fields and is not by itself proof of an IME defect. This audit does not disable security protections.")
}

let sources = TISCreateInputSourceList(nil, true)?.takeRetainedValue() as? [TISInputSource] ?? []
func value(_ source: TISInputSource, _ key: CFString) -> String {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return "<NULL>" }
    return String(describing: Unmanaged<AnyObject>.fromOpaque(pointer).takeUnretainedValue())
}
if let current = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() {
    print("CURRENT", value(current, kTISPropertyInputSourceID), "TYPE", value(current, kTISPropertyInputSourceType))
}
for source in sources where value(source, kTISPropertyInputSourceID).contains("guyi") {
    for key in [kTISPropertyInputSourceID, kTISPropertyInputSourceType, kTISPropertyInputSourceCategory,
                kTISPropertyInputSourceIsEnabled, kTISPropertyInputSourceIsSelectCapable, kTISPropertyBundleID] {
        print(key! as String, value(source, key!))
    }
}
