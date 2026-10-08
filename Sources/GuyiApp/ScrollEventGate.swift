import AppKit

/// Active only during scrolling capture. Keeps real wheel input queued while a
/// tagged, bounded scroll step is routed through WindowServer to the host.
@MainActor final class ScrollEventGate {
    static let forwardedTag: Int64 = 0x475559495343524C
    var consume: ((CGEventType, CGEvent) -> Bool)?
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    func start() -> Bool {
        let mask = [CGEventType.scrollWheel, .leftMouseDown, .leftMouseUp].reduce(CGEventMask(0)) { $0 | (1 << $1.rawValue) }
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let gate = Unmanaged<ScrollEventGate>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let port = gate.port { CGEvent.tapEnable(tap: port, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                if event.getIntegerValueField(.eventSourceUserData) == ScrollEventGate.forwardedTag { return Unmanaged.passUnretained(event) }
                return gate.consume?(type, event) == true ? nil : Unmanaged.passUnretained(event)
            }
        }, userInfo: pointer) else { return false }
        port = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }
    func stop() {
        if let port { CGEvent.tapEnable(tap: port, enable: false); CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil; source = nil; consume = nil
    }
}
