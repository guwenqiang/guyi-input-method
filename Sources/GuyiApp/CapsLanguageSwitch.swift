import AppKit
import Carbon
import IOKit.hidsystem
import GuyiCore

@MainActor final class CapsLanguageSwitch {
    static let shared = CapsLanguageSwitch()
    private var lastToggle = Date.distantPast
    private var keepPanelUntil = Date.distantPast
    var toggleLanguage: (() -> Bool)?
    var allowsSwitch: (() -> Bool)?

    func handlePhysicalState(eventHasLock: Bool) -> Bool {
        guard allowsSwitch?() != false, !IsSecureEventInputEnabled(),
              (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true else {
            InputSourceDiagnostics.record("caps-rejected-context", eventHasLock: eventHasLock)
            return false
        }
        guard
              let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID),
              (Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String)
                .hasPrefix("app.guyi.inputmethod.Guyi") else {
            InputSourceDiagnostics.record("caps-rejected-source", eventHasLock: eventHasLock)
            return false
        }
        let locked = Self.capsLockState() ?? eventHasLock
        let next: Language = locked ? .en : AppDelegate.shared.preferences.lastNonEnglishInputLanguage
        guard AppDelegate.shared.preferences.inputLanguage != next else {
            InputSourceDiagnostics.record("caps-already-in-mode", eventHasLock: eventHasLock)
            return true
        }
        if Date().timeIntervalSince(lastToggle) < 0.07 {
            InputSourceDiagnostics.record("caps-debounced", eventHasLock: eventHasLock)
            return true
        }
        guard toggleLanguage?() == true else {
            InputSourceDiagnostics.record("caps-no-controller", eventHasLock: eventHasLock)
            return false
        }
        lastToggle = Date()
        keepPanelUntil = Date().addingTimeInterval(0.25)
        InputSourceDiagnostics.record(locked ? "caps-to-en" : "caps-to-zh", eventHasLock: eventHasLock)
        if next != .en { clearCapsLockAfterSwitch() }
        return true
    }

    var keepingCandidatePanel: Bool { Date() < keepPanelUntil }

    private func clearCapsLockAfterSwitch() {
        InputSourceDiagnostics.record("caps-clear-lock")
        _ = Self.setCapsLock(false)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(40))
            _ = Self.setCapsLock(false)
        }
    }

    private static func withHIDConnection<T>(_ body: (io_connect_t) -> T?) -> T? {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return nil }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return nil }
        defer { IOServiceClose(connection) }
        return body(connection)
    }

    private static func capsLockState() -> Bool? {
        withHIDConnection { connection in
            var locked = false
            return IOHIDGetModifierLockState(connection, Int32(kIOHIDCapsLockState), &locked) == KERN_SUCCESS ? locked : nil
        }
    }

    private static func setCapsLock(_ locked: Bool) -> Bool {
        withHIDConnection { connection in
            IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), locked) == KERN_SUCCESS
        } ?? false
    }
}
