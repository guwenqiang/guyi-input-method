import AppKit
import Carbon
import Combine
import GuyiCore
import OSLog

/// Reads only explicitly selected text, never the document value or surrounding text.
@MainActor final class SelectionTranslationService {
    static let shared = SelectionTranslationService()
    private var preferences: Preferences?
    private var timer: Timer?
    private let model = CandidateModel()
    private var panel: CandidatePanel?
    private var observers: Set<AnyCancellable> = []
    private var hostPID: pid_t?
    private var lastSelection = ""
    private var dismissedSelection = ""
    private var selectionBeforeHostSwitch: (pid: pid_t, text: String)?
    private var clicks: UInt64 = 0
    private var clipboardCount = NSPasteboard.general.changeCount
    private var pendingClipboard: (text: String, ready: Date, pid: pid_t, mouseCount: UInt64)?
    private var explicitCopy: (pid: pid_t, time: Date)?
    private var anchor = NSRect.zero
    private var lastRead = Date.distantPast
    private var readingSelection = false
    private var inputRevision = 0
    private var grammarTask: Task<Void, Never>?
    private var grammarRevision = 0
    private var keyMonitor: Any?
    private var selectionMouseMonitor: Any?
    private var selectionPointer: (pid_t, NSPoint)?
    private var selectionMouseDown: (pid_t, NSPoint)?
    private var pendingVisualGesture: (pid: pid_t, start: NSPoint, end: NSPoint)?
    private var pendingSelectAll: (pid: pid_t, point: NSPoint)?
    private var visibleSelection: (pid: pid_t, text: String, bounds: NSRect)?
    private var exactCaptureInProgress = false
    private var pasteSuppressedUntil = Date.distantPast
    private var selectionEditSuppressedUntil = Date.distantPast
    private let routingLogger = Logger(subsystem: "app.guyi.inputmethod.Guyi", category: "SelectionRouting")
    private func audit(_ event: String, length: Int = 0) {
        guard UserDefaults.standard.bool(forKey: "diagnoseSelectionRouting") else { return }
        routingLogger.notice("event=\(event, privacy: .public) length=\(length) mouse=\(self.mouseCount) clipboard=\(self.clipboardCount)")
    }
    var suppressingAutomaticTranslation: Bool { Date() < pasteSuppressedUntil }
    func notePaste() {
        pasteSuppressedUntil = Date().addingTimeInterval(0.9)
        clipboardCount = NSPasteboard.general.changeCount
        pendingClipboard = nil
        if isShowing { close() }
    }
    func noteDeletion() {
        inputRevision += 1
        selectionEditSuppressedUntil = Date().addingTimeInterval(0.6)
        pendingVisualGesture = nil
        pendingSelectAll = nil
        visibleSelection = nil
        pendingClipboard = nil
        explicitCopy = nil
        if !model.original.isEmpty { lastSelection = model.original }
        close()
    }
    var isShowing: Bool { panel?.isVisible == true }
    private var mouseCount: UInt64 {
        UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: .leftMouseDown)) +
        UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: .rightMouseDown))
    }
    func start(preferences: Preferences) {
        guard timer == nil else { return }
        self.preferences = preferences
        model.retryTranslation = { [weak self] in self?.translate(forceRefresh: true) }
        model.clipboardMode = true
        model.restoreCollapsedLanguages()
        model.settings = { [weak self] in self?.close(); NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/GuYi输入法.app")) }
        model.toggleLanguage = { [weak self] language in
            guard let self, let preferences = self.preferences else { return }
            var languages = preferences.settings.selectionLanguages ?? [.en, .id]
            if languages.contains(language) { languages.removeAll { $0 == language } } else { languages.append(language) }
            preferences.saveSelectionLanguages(languages)
        }
        model.translationTargetsChanged = { [weak self] in self?.translate() }
        model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isShowing else { return }
                self.panel?.present(near: self.anchor, avoiding: self.anchor)
            }
        }.store(in: &observers)
        model.copyText = { [weak self] text in self?.copy(text) }
        model.learn = { [weak self] language in self?.learn(language) }
        model.translation.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.isShowing else { return }
                if let result = self.model.translation.result { self.model.language = result.source }
                self.panel?.present(near: self.anchor, avoiding: self.anchor)
            }
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: .guyiSelectionLanguagesChanged).sink { [weak self] _ in self?.translate() }.store(in: &observers)
        NotificationCenter.default.publisher(for: .guyiSelectionPauseChanged).sink { [weak self] _ in
            guard let self, let preferences = self.preferences else { return }
            if preferences.selectionTranslationPaused { self.close(); self.pendingClipboard = nil }
        }.store(in: &observers)
        NotificationCenter.default.publisher(for: .guyiSettingsChanged).sink { [weak self] _ in
            guard let self else { return }
            if preferences.settings.translateSelection == false && preferences.settings.translateClipboard == false { self.close() }
            else { self.translate() }
        }.store(in: &observers)
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // New typing/navigation ends the preview; Cmd-C may immediately create
            // a new explicit clipboard request, handled by the normal poll.
            let front = NSWorkspace.shared.frontmostApplication
            let pointer = NSEvent.mouseLocation
            Task { @MainActor in
                guard let self else { return }
                if let preferences = self.preferences,
                   InputShortcuts.action(key: UInt32(event.keyCode),
                       modifiers: ShortcutRecorder.carbonModifiers(event.modifierFlags),
                       settings: preferences.settings, hasCandidates: false) == "toggleSelectionTranslation" {
                    preferences.toggleSelectionTranslation()
                    return
                }
                if [51, 117].contains(event.keyCode) { self.noteDeletion(); return }
                if self.exactCaptureInProgress { return }
                self.inputRevision += 1
                self.visibleSelection = nil
                let selectAll = event.keyCode == 0 && event.modifierFlags.contains(.command) &&
                    event.modifierFlags.intersection([.shift, .control, .option]).isEmpty
                self.pendingSelectAll = selectAll ? front.map { ($0.processIdentifier, pointer) } : nil
                if selectAll {
                    Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .milliseconds(80))
                        await self?.poll()
                    }
                }
                let copying = event.keyCode == 8 && event.modifierFlags.contains(.command)
                self.explicitCopy = copying ? front.map { ($0.processIdentifier, Date()) } : nil
                if copying { self.lastSelection = ""; self.dismissedSelection = "" }
                if event.keyCode == 9 && event.modifierFlags.contains(.command) { self.notePaste() }
                else {
                    if !copying { self.pendingClipboard = nil }
                    if self.isShowing { self.close() }
                    if event.keyCode == 0 && event.modifierFlags.contains(.command) ||
                        [115, 119, 123, 124, 125, 126].contains(event.keyCode) && event.modifierFlags.contains(.shift) {
                        self.dismissedSelection = ""
                    }
                }
            }
        }
        clicks = mouseCount
        selectionMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] event in
            let pointer = NSEvent.mouseLocation
            let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
            let down = event.type == .leftMouseDown, clickCount = event.clickCount
            Task { @MainActor in
                guard let self, let pid else { return }
                if down {
                    self.audit("mouse-down")
                    self.selectionMouseDown = (pid, pointer)
                    self.pendingVisualGesture = nil
                    self.pendingSelectAll = nil
                    if self.panel?.frame.contains(pointer) != true { self.visibleSelection = nil }
                    self.explicitCopy = nil
                    self.pendingClipboard = nil
                    self.clipboardCount = NSPasteboard.general.changeCount
                    return
                }
                self.selectionPointer = (pid, pointer)
                let start = self.selectionMouseDown
                self.selectionMouseDown = nil
                let dragged = start?.0 == pid && hypot(pointer.x - start!.1.x, pointer.y - start!.1.y) >= 4
                if clickCount >= 2 || dragged {
                    self.audit("selection-gesture")
                    // Re-selecting identical text is a new explicit gesture, even
                    // if polling never observed the brief empty range in between.
                    self.close()
                    self.clicks = self.mouseCount
                    self.dismissedSelection = ""
                    if self.selectionBeforeHostSwitch?.pid == pid { self.selectionBeforeHostSwitch = nil }
                    if dragged, let start { self.pendingVisualGesture = (pid, start.1, pointer) }
                    else if clickCount >= 2 { self.pendingVisualGesture = (pid, pointer, pointer) }
                }
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
    }
    func close() {
        dismissedSelection = lastSelection
        panel?.orderOut(nil)
        model.translation.invalidate()
        model.original = ""
        resetLesson()
        TranslationSpeech.shared.stop()
    }
    func frontApplicationChanged() {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              pid != hostPID else { return }
        if let hostPID, isShowing, !model.original.isEmpty {
            selectionBeforeHostSwitch = (hostPID, model.original)
        }
        close()
        hostPID = pid
        lastSelection = ""
        dismissedSelection = selectionBeforeHostSwitch?.pid == pid ? selectionBeforeHostSwitch!.text : ""
        pendingClipboard = nil
        clipboardCount = NSPasteboard.general.changeCount
        visibleSelection = nil
        if pendingVisualGesture?.pid != pid { pendingVisualGesture = nil }
        if pendingSelectAll?.pid != pid { pendingSelectAll = nil }
        explicitCopy = nil
    }
    private let selectedTextReader = SelectedTextReader()
    private func poll() async {
        guard !readingSelection else { return }
        readingSelection = true
        defer { readingSelection = false }
        guard let preferences else { return }
        guard !preferences.selectionTranslationPaused else { return }
        guard preferences.settings.translateSelection != false || preferences.settings.translateClipboard != false else { return }
        guard !TranslationPrivacy.protectedContext() else {
            pendingClipboard = nil; clipboardCount = NSPasteboard.general.changeCount
            visibleSelection = nil
            close(); lastSelection = ""; dismissedSelection = ""
            return
        }
        guard !IsSecureEventInputEnabled(),
              (CGSessionCopyCurrentDictionary() as NSDictionary?)?["CGSSessionScreenIsLocked"] as? Bool != true,
              let front = NSWorkspace.shared.frontmostApplication,
              !["app.guyi.inputmethod.Guyi", "app.guyi.launcher"].contains(front.bundleIdentifier ?? "") else { return }
        // Finder exposes selected file names as AX selected text. Opening a file
        // with a double-click must not be interpreted as a translation gesture.
        if front.bundleIdentifier == "com.apple.finder" {
            pendingVisualGesture = nil
            pendingSelectAll = nil
            pendingClipboard = nil
            visibleSelection = nil
            clipboardCount = NSPasteboard.general.changeCount
            if isShowing { close() }
            return
        }
        let privateField = await TranslationPrivacy.excludedFocusedField(pid: front.processIdentifier)
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier else { return }
        if privateField {
            pendingClipboard = nil; clipboardCount = NSPasteboard.general.changeCount
            pendingVisualGesture = nil
            pendingSelectAll = nil
            visibleSelection = nil
            close(); lastSelection = ""; dismissedSelection = ""
            return
        }
        if front.processIdentifier != hostPID {
            frontApplicationChanged()
        }
        let count = mouseCount
        if count != clicks {
            audit("mouse-count-changed")
            clicks = count
            pendingClipboard = nil
            explicitCopy = nil
            clipboardCount = NSPasteboard.general.changeCount
            if panel?.frame.contains(NSEvent.mouseLocation) != true { visibleSelection = nil }
            if isShowing, panel?.frame.contains(NSEvent.mouseLocation) != true { close() }
        }
        guard !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return }
        let pasteboard = NSPasteboard.general
        let protectedClipboard = TranslationPrivacy.protectedClipboard(pasteboard)
        if protectedClipboard { pendingClipboard = nil; clipboardCount = pasteboard.changeCount }
        if suppressingAutomaticTranslation {
            clipboardCount = pasteboard.changeCount
            pendingClipboard = nil
            dismissedSelection = lastSelection
            return
        }
        if Date() < selectionEditSuppressedUntil {
            clipboardCount = pasteboard.changeCount
            pendingClipboard = nil
            return
        }
        var found: (String, NSRect)? = visibleSelection?.pid == front.processIdentifier
            ? visibleSelection.map { ($0.text, $0.bounds) } : nil
        var source = found == nil ? "none" : "cached-selection"
        var readSelection = false
        let requirePointerMatch = pendingVisualGesture?.pid == front.processIdentifier
        if found == nil, !(pendingSelectAll != nil && preferences.settings.preciseSelectionCompatibility == true),
           preferences.settings.translateSelection != false, AXIsProcessTrusted(),
           Date().timeIntervalSince(lastRead) > 0.35 {
            lastRead = Date()
            readSelection = true
            let revision = inputRevision, selectionClicks = mouseCount
            let pointer = selectionPointer?.0 == front.processIdentifier ? selectionPointer?.1 : nil
            found = await selectedTextReader.readAsync(pid: front.processIdentifier, selectionPointer: pointer,
                                                      requirePointerMatch: requirePointerMatch)
            if found != nil || pendingVisualGesture != nil || pendingSelectAll != nil || !lastSelection.isEmpty {
                audit(found == nil ? "ax-empty" : "ax-found", length: found?.0.count ?? 0)
            }
            if found != nil { source = "ax" }
            guard revision == inputRevision, selectionClicks == mouseCount,
                  !preferences.selectionTranslationPaused, !suppressingAutomaticTranslation,
                  !TranslationPrivacy.protectedContext(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier else { return }
        }
        let exactGesture: (pid: pid_t, start: NSPoint, end: NSPoint)? = pendingVisualGesture ??
            pendingSelectAll.map { request in (pid: request.pid, start: request.point, end: request.point) }
        if found == nil, preferences.settings.translateSelection != false,
           preferences.settings.preciseSelectionCompatibility != false,
           let gesture = exactGesture,
           gesture.pid == front.processIdentifier {
            pendingVisualGesture = nil
            pendingSelectAll = nil
            exactCaptureInProgress = true
            let revision = inputRevision
            let selectionClicks = mouseCount
            let exact = await ExactSelectionCapture.read(pid: gesture.pid, mouseCount: selectionClicks) { [weak self] in
                self?.mouseCount ?? 0
            }
            exactCaptureInProgress = false
            clipboardCount = NSPasteboard.general.changeCount
            explicitCopy = nil
            pendingClipboard = nil
            guard revision == inputRevision, selectionClicks == mouseCount,
                  !preferences.selectionTranslationPaused, !suppressingAutomaticTranslation,
                  !TranslationPrivacy.protectedContext(),
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == front.processIdentifier else { return }
            if let exact {
                let bounds = NSRect(x: gesture.end.x, y: gesture.end.y - 9, width: 1, height: 18)
                found = (exact, bounds)
                source = "exact-selection"
                visibleSelection = (front.processIdentifier, exact, bounds)
            }
            readSelection = true
        } else if found == nil, pendingVisualGesture?.pid == front.processIdentifier {
            pendingVisualGesture = nil
        }
        if let found, !SensitiveContentPolicy.resemblesSecret(found.0) {
            pendingVisualGesture = nil
            pendingClipboard = nil
            clipboardCount = pasteboard.changeCount
            if found.0 != lastSelection {
                if found.0 != dismissedSelection { dismissedSelection = "" }
                if preferences.settings.copySelectionAutomatically == true {
                    pasteboard.clearContents(); pasteboard.setString(found.0, forType: .string)
                    clipboardCount = pasteboard.changeCount
                }
            }
            lastSelection = found.0
            if found.0 != dismissedSelection, model.original != found.0 || !isShowing {
                show(found.0, near: found.1, source: source)
            }
        }
        if found == nil, readSelection {
            if !lastSelection.isEmpty, isShowing { close() }
            lastSelection = ""
        }
        if !protectedClipboard, pasteboard.changeCount != clipboardCount {
            audit("clipboard-changed")
            clipboardCount = pasteboard.changeCount
            pendingClipboard = nil
            if preferences.settings.translateClipboard != false, found == nil,
               let explicitCopy, explicitCopy.pid == front.processIdentifier,
               Date().timeIntervalSince(explicitCopy.time) < 1.5,
               let text = pasteboard.string(forType: .string),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4_000 {
                pendingClipboard = (text, Date().addingTimeInterval(0.4), front.processIdentifier, mouseCount)
            }
            explicitCopy = nil
        }
        if let pending = pendingClipboard, Date() >= pending.ready {
            pendingClipboard = nil
            // Selection tools can temporarily copy and restore the pasteboard.
            // A valid current selection always takes priority over clipboard changes.
            guard pending.pid == front.processIdentifier, pending.mouseCount == mouseCount,
                  pendingVisualGesture == nil, lastSelection.isEmpty,
                  !TranslationPrivacy.protectedClipboard(pasteboard), !TranslationPrivacy.protectedContext(),
                  pasteboard.string(forType: .string) == pending.text else { return }
            let p = NSEvent.mouseLocation
            show(pending.text, near: NSRect(x: p.x, y: p.y - 9, width: 1, height: 18), source: "clipboard")
        }
    }

    private func show(_ text: String, near bounds: NSRect, source: String) {
        audit("show-\(source)", length: text.count)
        guard let preferences else { return }
        guard SelectionTranslationPolicy.shouldTranslate(text, settings: preferences.settings, interfaceLanguage: InterfaceLanguage.shared.code),
              !(preferences.settings.selectionLanguages ?? [.en, .id]).isEmpty else { close(); return }
        if model.original != text {
            model.translation.invalidate()
            resetLesson(); model.expanded = false; model.selectingLanguages = false; TranslationSpeech.shared.stop()
        }
        model.original = text
        model.themeSettings = preferences.settings
        model.enabledLanguages = preferences.settings.selectionLanguages ?? [.en, .id]
        model.clipboardMode = true
        model.language = SelectionTranslationPolicy.detectedLanguage(text)
        anchor = NSRect(x: bounds.minX, y: bounds.minY, width: max(1, bounds.width), height: min(280, max(18, bounds.height)))
        if panel == nil { panel = CandidatePanel(model: model) }
        panel?.present(near: anchor, avoiding: anchor)
        translate()
    }
    private func translate(forceRefresh: Bool = false) {
        guard let preferences, !preferences.selectionTranslationPaused, isShowing, !model.original.isEmpty else { return }
        guard SelectionTranslationPolicy.shouldTranslate(model.original, settings: preferences.settings, interfaceLanguage: InterfaceLanguage.shared.code) else { close(); return }
        resetLesson()
        model.enabledLanguages = preferences.settings.selectionLanguages ?? [.en, .id]
        var settings = preferences.settings
        settings.source = .auto; settings.enabledLanguages = model.requestedLanguages; settings.translateWholeSelection = true
        // Whole selections often contain several sentences and need a little
        // more time for structured multi-target output than a short keystroke.
        settings.timeoutSeconds = max(settings.timeoutSeconds, 45)
        model.translation.update(text: model.original, composing: false, settings: settings,
                                 apiKey: preferences.apiKey, immediate: true, forceRefresh: forceRefresh)
    }
    private func resetLesson() {
        grammarTask?.cancel(); grammarTask = nil; grammarRevision += 1
        model.lesson = nil; model.lessonStatus = ""
    }
    private func learn(_ language: Language) {
        guard let preferences, isShowing, let result = model.translation.result,
              !result.text(for: language).isEmpty else { return }
        resetLesson()
        let revision = grammarRevision, original = model.original
        let settings = preferences.settings, key = preferences.apiKey
        model.lessonStatus = "正在整理语法说明…"
        model.lessonLanguage = language
        grammarTask = Task { @MainActor [weak self] in
            do {
                let lesson = try await GrammarTeacher().explain(original: original, translation: result.text(for: language), language: language, settings: settings, apiKey: key)
                guard let self, !Task.isCancelled, self.isShowing, revision == self.grammarRevision else { return }
                self.model.lesson = lesson
            } catch {
                guard let self, !Task.isCancelled, revision == self.grammarRevision else { return }
                self.model.lessonStatus = error.localizedDescription
            }
        }
    }
    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let p = NSPasteboard.general; p.clearContents(); p.setString(text, forType: .string)
        clipboardCount = p.changeCount
        pendingClipboard = nil
        model.copiedText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.model.copiedText = "" }
    }
}
