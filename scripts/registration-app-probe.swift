import AppKit
import Carbon

final class RegistrationAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true else {
            exit(2)
        }
        let path = NSHomeDirectory() + "/Library/Input Methods/GuYi输入法.app"
        let registration = TISRegisterInputSource(URL(fileURLWithPath: path) as CFURL)
        NSLog("GuYi registrar: registration=%d", registration)
        guard registration == noErr else { exit(1) }
        let filter = [kTISPropertyBundleID as String: "app.guyi.inputmethod.Guyi"] as CFDictionary
        let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
        for source in sources {
            NSLog("GuYi registrar: enable=%d", TISEnableInputSource(source))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { NSApp.terminate(nil) }
    }
}

let application = NSApplication.shared
let delegate = RegistrationAppDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
