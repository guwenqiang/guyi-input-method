import AppKit
import Carbon
import OSLog

enum InputSourceDiagnostics {
    private static let logger = Logger(subsystem: "app.guyi.inputmethod.Guyi", category: "InputSource")

    static var enabled: Bool { UserDefaults.standard.bool(forKey: "diagnoseInputSources") }

    static func record(_ stage: String, eventHasLock: Bool? = nil) {
        guard enabled else { return }
        let source: String
        if let input = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
           let pointer = TISGetInputSourceProperty(input, kTISPropertyInputSourceID) {
            source = Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
        } else { source = "unavailable" }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unavailable"
        let lock = eventHasLock.map { $0 ? "on" : "off" } ?? "unknown"
        let secure = IsSecureEventInputEnabled()
        logger.notice("stage=\(stage, privacy: .public) source=\(source, privacy: .public) app=\(app, privacy: .public) eventCaps=\(lock, privacy: .public) secure=\(secure)")
    }
}
