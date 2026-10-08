import AppKit
import Carbon
import IOKit.hidsystem
import IOKit.hid
import OSLog

/// Keeps GuYi/ABC round trips consistent across hosts, including native
/// switches that consume Caps events or restore another Chinese input source.
@MainActor final class TerminalCapsLockSwitch {
    static let shared = TerminalCapsLockSwitch()
    private var monitor: Any?
    private var keyboard: IOHIDManager?
    private var lastHardwarePress = Date.distantPast
    private var pressedCapsElements: Set<UInt> = []
    private var pending: Task<Void, Never>?
    private var returnSource: String?
    private var returnHost: pid_t?
    private var lastSwitch = Date.distantPast
    private var observedSource = TerminalCapsLockSwitch.currentID()
    private var previousSource: String?
    private var sourceChangeTime = Date.distantPast
    private var sourceRevision = 0
    private var switchRevision = 0
    private var settlingSwitch: (revision: Int, target: String, host: pid_t, mouse: UInt64, until: Date)?
    private var mouseCount: UInt64 { UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown)) }
    private func trace(_ event: String) {
        guard UserDefaults.standard.bool(forKey: "capsSwitchDiagnostics") else { return }
        let source = Self.currentID() ?? "none", target = settlingSwitch?.target ?? "none", returning = returnSource ?? "none", host = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none"
        Logger(subsystem: "app.guyi.inputmethod.Guyi", category: "CapsSwitch").notice("\(event, privacy: .public) source=\(source, privacy: .public) target=\(target, privacy: .public) return=\(returning, privacy: .public) host=\(host, privacy: .public)")
    }
    var prepareSwitch: (() -> Void)?
    var allowsSwitch: (() -> Bool)?
    func start() {
        guard monitor == nil else { return }
        startHardware()
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.flagsChanged, .keyDown, .leftMouseDown]) { [weak self] event in
            if event.type == .leftMouseDown ||
                event.type == .flagsChanged && event.keyCode != 57 && !event.modifierFlags.intersection([.control, .function]).isEmpty ||
                event.type == .keyDown && event.keyCode == 49 && !event.modifierFlags.intersection([.command, .control]).isEmpty {
                Task { @MainActor in self?.settlingSwitch = nil }
                return
            }
            guard event.type == .flagsChanged, event.keyCode == 57, event.modifierFlags.contains(.capsLock),
                  event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty else { return }
            Task { @MainActor in
                guard let self, self.keyboard == nil, Date().timeIntervalSince(self.lastHardwarePress) > 0.5 else { return }
                self.handleCapsLockChange()
            }
        }
    }
    static var hardwareAccessGranted: Bool { IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted }
    func refreshHardwareAccess() {
        if keyboard == nil, Self.hardwareAccessGranted { startHardware() }
    }
    func requestHardwareAccess() {
        if IOHIDRequestAccess(kIOHIDRequestTypeListenEvent) { refreshHardwareAccess() }
        else if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") { NSWorkspace.shared.open(url) }
    }
    private func startHardware() {
        guard keyboard == nil else { return }
        // macOS can consume a short Caps language-switch before either NSEvent
        // or a CGEvent tap receives it. Match only Caps Lock at the HID element
        // level: no other keyboard values are delivered to this callback.
        let keyboard = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(keyboard, [kIOHIDDeviceUsagePageKey: kHIDPage_GenericDesktop,
                                               kIOHIDDeviceUsageKey: kHIDUsage_GD_Keyboard] as CFDictionary)
        IOHIDManagerSetInputValueMatching(keyboard, [kIOHIDElementUsagePageKey: kHIDPage_KeyboardOrKeypad,
                                                   kIOHIDElementUsageKey: kHIDUsage_KeyboardCapsLock] as CFDictionary)
        IOHIDManagerRegisterInputValueCallback(keyboard, { context, result, _, value in
            guard result == kIOReturnSuccess, let context else { return }
            let element = IOHIDValueGetElement(value)
            guard IOHIDElementGetUsagePage(element) == kHIDPage_KeyboardOrKeypad,
                  IOHIDElementGetUsage(element) == kHIDUsage_KeyboardCapsLock else { return }
            let handler = Unmanaged<TerminalCapsLockSwitch>.fromOpaque(context).takeUnretainedValue()
            let pressed = IOHIDValueGetIntegerValue(value) == 1
            let identity = UInt(bitPattern: Unmanaged.passUnretained(element).toOpaque())
            // This callback is scheduled on CFRunLoopGetMain. Handle edges in
            // delivery order rather than dropping fast presses with a timer.
            MainActor.assumeIsolated {
                if !pressed { handler.pressedCapsElements.remove(identity); return }
                guard handler.pressedCapsElements.insert(identity).inserted,
                      CGEventSource.flagsState(.combinedSessionState).intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty else { return }
                handler.lastHardwarePress = Date()
                handler.trace("physical-caps-down")
                handler.handleCapsLockChange(hardware: true)
            }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDManagerScheduleWithRunLoop(keyboard, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let status = IOHIDManagerOpen(keyboard, IOOptionBits(kIOHIDOptionsTypeNone))
        trace("hardware-open status=\(status) granted=\(Self.hardwareAccessGranted)")
        if status == kIOReturnSuccess {
            self.keyboard = keyboard
        } else {
            IOHIDManagerUnscheduleFromRunLoop(keyboard, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        }
    }
    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              let value = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return nil }
        return Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
    }
    func sourceChanged() {
        guard let id = Self.currentID() else { return }
        if id != observedSource {
            previousSource = observedSource; observedSource = id; sourceChangeTime = Date()
            sourceRevision += 1
        }
        if let switchState = settlingSwitch, Date() < switchState.until,
           NSWorkspace.shared.frontmostApplication?.processIdentifier == switchState.host,
           mouseCount == switchState.mouse, id != switchState.target {
            trace("late-source-change")
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(25))
                self?.settle(switchState.revision)
            }
            return
        }
        guard id != "com.apple.keylayout.ABC" else { return }
        let revision = sourceRevision
        // Source notifications can arrive before the Caps flags callback. Wait
        // for that in-flight event before treating this as a manual selection.
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(350))
            guard let self, self.sourceRevision == revision, Self.currentID() == id,
                  self.settlingSwitch == nil || Date() >= self.settlingSwitch!.until else { return }
            self.returnSource = nil; self.returnHost = nil
        }
    }
    func handleCapsLockChange(hardware: Bool = false) {
        guard let host = NSWorkspace.shared.frontmostApplication,
              allowsSwitch?() != false,
              UserDefaults.standard.object(forKey: "TISRomanSwitchState") as? Int == 1,
              !IsSecureEventInputEnabled(), (hardware || Date().timeIntervalSince(lastSwitch) > 0.35),
              let before = Self.currentID() else { return }
        let nativeJustLeftGuYi = before == "com.apple.keylayout.ABC" && returnSource == nil &&
            (observedSource?.hasPrefix("app.guyi.inputmethod.Guyi") == true ||
             previousSource?.hasPrefix("app.guyi.inputmethod.Guyi") == true && Date().timeIntervalSince(sourceChangeTime) < 0.25)
        let recent = settlingSwitch.flatMap { state -> String? in
            hardware && state.host == host.processIdentifier && state.mouse == mouseCount && Date() < state.until ? state.target : nil
        }
        let origin = recent ?? (nativeJustLeftGuYi ? (observedSource?.hasPrefix("app.guyi.inputmethod.Guyi") == true ? observedSource! : previousSource!) : before)
        let destination: String
        let nativeJustReturned = before.hasPrefix("app.guyi.inputmethod.Guyi") && (observedSource == "com.apple.keylayout.ABC" || previousSource == "com.apple.keylayout.ABC" && Date().timeIntervalSince(sourceChangeTime) < 0.25)
        let returningToGuYi = (!origin.hasPrefix("app.guyi.inputmethod.Guyi") || recent == nil && nativeJustReturned) && returnHost == host.processIdentifier && returnSource != nil
        if returningToGuYi, let saved = returnSource { destination = saved }
        else if origin.hasPrefix("app.guyi.inputmethod.Guyi") { destination = "com.apple.keylayout.ABC" }
        else { return }
        // Track the user's intended phase immediately, so a second physical
        // press can supersede an in-flight native switch without losing order.
        returnSource = returningToGuYi ? nil : origin
        returnHost = returningToGuYi ? nil : host.processIdentifier
        switchRevision += 1
        settlingSwitch = (switchRevision, destination, host.processIdentifier, mouseCount, Date().addingTimeInterval(1))
        trace(hardware ? "hardware-caps" : "fallback-caps")
        pending?.cancel()
        pending = Task { [weak self] in
            // Native switching gets first chance; do nothing if it succeeded.
            do { try await Task.sleep(for: .milliseconds(160)) } catch { return }
            guard let self, !Task.isCancelled,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier,
                  !IsSecureEventInputEnabled(),
                  (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true else { return }
            guard let current = Self.currentID() else { return }
            if returningToGuYi {
                // macOS may restore another Chinese IME from its own history.
                // Complete only our recorded GuYi→ABC round trip in this host.
                if current == destination { self.returnSource = nil; self.returnHost = nil; return }
            } else {
                // Native success still belongs to this round trip. Previously
                // this branch returned before remembering GuYi, so the next
                // Caps press could restore WeType from macOS's source history.
                if current == destination {
                    self.returnSource = origin; self.returnHost = host.processIdentifier
                    self.lastSwitch = Date(); Self.clearCapsLock(); return
                }
                guard current == before, hardware || CGEventSource.flagsState(.combinedSessionState).contains(.maskAlphaShift) else { return }
            }
            let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: destination] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] ?? []
            guard let target = sources.first else { return }
            if Self.currentID()?.hasPrefix("app.guyi.inputmethod.Guyi") == true { self.prepareSwitch?() }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == host.processIdentifier, TISSelectInputSource(target) == noErr else { return }
            self.lastSwitch = Date()
            self.returnSource = origin.hasPrefix("app.guyi.inputmethod.Guyi") ? origin : nil
            self.returnHost = self.returnSource == nil ? nil : host.processIdentifier
            Self.clearCapsLock()
        }
    }
    private func settle(_ revision: Int) {
        guard let state = settlingSwitch, state.revision == revision, Date() < state.until,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == state.host,
              mouseCount == state.mouse, allowsSwitch?() != false, !IsSecureEventInputEnabled(),
              (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true,
              Self.currentID() != state.target else { return }
        let sources = TISCreateInputSourceList([kTISPropertyInputSourceID as String: state.target] as CFDictionary, false)?.takeRetainedValue() as? [TISInputSource] ?? []
        guard let target = sources.first else { return }
        if Self.currentID()?.hasPrefix("app.guyi.inputmethod.Guyi") == true { prepareSwitch?() }
        if TISSelectInputSource(target) == noErr { Self.clearCapsLock(); trace("settled-late-native-change") }
    }
    @discardableResult static func clearCapsLock() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOHIDSystem"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        var connection: io_connect_t = 0
        guard IOServiceOpen(service, mach_task_self_, UInt32(kIOHIDParamConnectType), &connection) == KERN_SUCCESS else { return false }
        defer { IOServiceClose(connection) }
        return IOHIDSetModifierLockState(connection, Int32(kIOHIDCapsLockState), false) == KERN_SUCCESS
    }
}
