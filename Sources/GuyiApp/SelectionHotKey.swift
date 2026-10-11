import AppKit
import Carbon
import GuyiCore

@MainActor final class SelectionHotKey {
    static let shared = SelectionHotKey()
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var recording = false
    private var preferences: Preferences?
    var registered: Bool { hotKey != nil }

    private init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            guard GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID),
                                    nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr,
                  id.signature == 0x47555953, id.id == 1 else { return OSStatus(eventNotHandledErr) }
            Task { @MainActor in SelectionHotKey.shared.preferences?.toggleSelectionTranslation() }
            return noErr
        }, 1, &type, nil, &handler)
    }

    func configure(preferences: Preferences) {
        self.preferences = preferences
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        let binding = InputShortcuts.binding("toggleSelectionTranslation", settings: preferences.settings)
        guard !recording, binding.enabled, binding.key < 128, binding.modifiers != 0,
              preferences.settings.translateSelection != false || preferences.settings.translateClipboard != false else { return }
        _ = RegisterEventHotKey(binding.key, binding.modifiers,
                                EventHotKeyID(signature: 0x47555953, id: 1),
                                GetApplicationEventTarget(), 0, &hotKey)
    }

    func pauseRecording(_ paused: Bool) {
        recording = paused
        if let preferences { configure(preferences: preferences) }
    }
}
