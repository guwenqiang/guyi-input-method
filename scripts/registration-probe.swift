import AppKit
import InputMethodKit

@objc(RegistrationProbeController)
final class RegistrationProbeController: IMKInputController {
    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue) }
    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool { false }
}

final class RegistrationProbeDelegate: NSObject, NSApplicationDelegate {
    var server: IMKServer?
    func applicationDidFinishLaunching(_ notification: Notification) {
        guard let name = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String else { exit(1) }
        server = IMKServer(name: name, bundleIdentifier: Bundle.main.bundleIdentifier)
    }
}

let application = NSApplication.shared
let delegate = RegistrationProbeDelegate()
application.setActivationPolicy(.accessory)
application.delegate = delegate
application.run()
