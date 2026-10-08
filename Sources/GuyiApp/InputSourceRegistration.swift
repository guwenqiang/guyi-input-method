import AppKit
import Carbon

enum InputSourceRegistration {
    static func run(bundle: Bundle = .main) -> Int32 {
        guard (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true else {
            print("Registration blocked: unlock macOS first.")
            return 2
        }
        let identifier = "app.guyi.inputmethod.Guyi"
        let allowed = ["/Library/Input Methods", NSHomeDirectory() + "/Library/Input Methods"]
        guard bundle.bundleIdentifier == identifier,
              allowed.contains(bundle.bundleURL.deletingLastPathComponent().path) else {
            print("Registration blocked: run the installed GuYi bundle, not a build or staging copy.")
            return 2
        }
        let status = TISRegisterInputSource(bundle.bundleURL as CFURL)
        guard status == noErr else { print("Registration failed:", status); return 1 }
        let rootID = bundle.object(forInfoDictionaryKey: "TISInputSourceID") as? String ?? identifier
        let container = bundle.object(forInfoDictionaryKey: "ComponentInputModeDict") as? [String: Any]
        let modes = container?["tsInputModeListKey"] as? [String: Any] ?? [:]
        let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
        for expected in [rootID] + modes.keys.sorted() {
            let sources = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] ?? []
            guard let source = sources.first(where: { source in
                guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return false }
                return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String == expected
            }) else { print("Registration missing source:", expected); return 1 }
            // Registration refreshes the installed bundle. Enabling is a separate
            // user-authorized system operation: on macOS 26, TISEnableInputSource
            // can return noErr before its consent dialog has been answered.
            _ = source
            print("Registered declared source:", expected)
        }
        let persisted = CFPreferencesCopyAppValue("AppleEnabledThirdPartyInputSources" as CFString,
                                                  "com.apple.inputsources" as CFString) as? [[String: Any]] ?? []
        let ownEntries = persisted.filter { $0["Bundle ID"] as? String == identifier }
        let enabledModes = Set(ownEntries.compactMap { $0["Input Mode"] as? String })
        let complete = Set(modes.keys).isSubset(of: enabledModes)
        print(complete ? "Existing enabled input modes preserved." : "Add GuYi in System Settings > Keyboard > Text Input. Registration alone does not enable it.")
        print("Select GuYi in a real text field to verify activation; no input-source preferences were changed.")
        return 0
    }
}
