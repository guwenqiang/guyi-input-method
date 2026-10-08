import AppKit
import InputMethodKit
import Combine
import GuyiCore
import Carbon
import OSLog

@objc(GuyiInputController)
@MainActor
final class GuyiInputController: IMKInputController {
    private let engine = RimeEngine()
    private weak var eventClient: IMKTextInput?
    private var inputClient: IMKTextInput? { eventClient ?? client() }
    private var sessionHostPID: pid_t?
    private let model = CandidateModel()
    private var panel: CandidatePanel?
    private var draft = ""
    private var sentenceNeedsConfirmation = false
    private var language = Language.zh
    private var active = false
    private var inputModeIdentifier = "app.guyi.inputmethod.Guyi.pinyin"
    private var caret = NSRect.zero
    private var caretGeometry = CaretGeometry()
    private var compositionRect = NSRect.zero
    private var caretMouseCount: UInt64?
    private var caretWindowOrigin: CGPoint?
    private var caretUpdateTask: Task<Void, Never>?
    private var inlineCursor = 0
    private var observers: Set<AnyCancellable> = []
    private var waitingShortcutLanguage: Language?
    private var waitingShortcutMessage: String { ShortcutMessages.text(.notReady) }
    private var lastTranslationShortcutKey: UInt16?
    private var grammarTask: Task<Void, Never>?
    private var grammarRevision = 0
    private var clipboardTimer: Timer?
    private var clipboardChange = 0
    private var pendingClipboard: String?
    private var clipboardAnchor: NSRect?
    private var clipboardMouseCount: UInt64?
    private var observedSelection: NSRange?
    private var observedSelectionText: String?
    private var hotwordCandidates: Set<String> = []
    private var candidateEngineIndices: [Int?] = []
    private var lastChosenPhrase: (code: String, text: String, time: Date, clicks: UInt64)?
    private var previousCommittedCharacter: Character?
    private var previousLatinWord = ""
    private var literalToken: String?
    private var literalMouse: UInt64?
    private var previousCommittedMouseCount: UInt64?
    private var numericExpression = ""
    private var numericExpressionTooLong = false
    private var mouseDownCount: UInt64 {
        [CGEventType.leftMouseDown, .rightMouseDown, .otherMouseDown].reduce(0) {
            $0 + UInt64(CGEventSource.counterForEventType(.combinedSessionState, eventType: $1))
        }
    }
    private var preferences: Preferences { AppDelegate.shared.preferences }
    private var bypassClient: Bool { InputSafety.bypassInputMethod(bundleIdentifier: inputClient?.bundleIdentifier()) || SensitiveContentPolicy.protectedApplication(inputClient?.bundleIdentifier()) || IsSecureEventInputEnabled() }
    private var ownsCurrentInputSource: Bool {
        guard InputSafety.allowsClientAccess(active: active, currentController: AppDelegate.shared.currentController === self,
                                             hasClient: inputClient != nil, sessionHostPID: sessionHostPID,
                                             foregroundPID: NSWorkspace.shared.frontmostApplication?.processIdentifier) else { return false }
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue(),
              TISGetInputSourceProperty(source, kTISPropertyInputSourceType) != nil else { return false }
        return true
    }

    override init!(server: IMKServer!, delegate: Any!, client: Any!) {
        super.init(server: server, delegate: delegate, client: client)
        eventClient = client as? IMKTextInput
    }

    override func activateServer(_ sender: Any!) {
        resetPunctuationContext()
        caretGeometry = CaretGeometry()
        if let sender = sender as? IMKTextInput { eventClient = sender }
        let foreground = NSWorkspace.shared.frontmostApplication
        sessionHostPID = inputClient?.bundleIdentifier() == foreground?.bundleIdentifier ? foreground?.processIdentifier : nil
        if bypassClient {
            endSession()
            return
        }
        active = true
        language = preferences.inputLanguage
        updateCaret()
        engine.learning(preferences.settings.learnInput)
        if observers.isEmpty {
            model.pick = { [weak self] in self?.choose($0) }
            model.insert = { [weak self] in self?.insertTranslation($0) }
            model.copyText = { [weak self] in self?.copyPanelText($0) }
            model.learn = { [weak self] in self?.learn($0) }
            model.retryTranslation = { [weak self] in
                guard let self, self.active, self.ownsCurrentInputSource else { return }
                self.translate(immediate: true)
            }
            model.settings = { AppDelegate.shared.showSettings() }
            model.cycle = { [weak self] in self?.cycleLanguage() }
            model.turnPage = { [weak self] in self?.turnPage($0) }
            model.toggleLanguage = { [weak self] in self?.toggleLanguage($0) }
            model.toggleSentence = { [weak self] in self?.preferences.toggleSentenceMode() }
            model.emoji = { [weak self] in self?.showEmoji() }
            NotificationCenter.default.publisher(for: .guyiSentenceModeChanged).sink { [weak self] _ in
                guard let self else { return }
                self.model.sentenceMode = self.preferences.settings.sentenceComposition == true
            }.store(in: &observers)
            model.translation.objectWillChange.sink { [weak self] in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if self.model.clipboardMode, let result = self.model.translation.result { self.model.language = result.source }
                    if let target = self.waitingShortcutLanguage,
                       self.model.translation.selectableText(for: target) != nil || !self.model.translation.busy {
                        self.clearShortcutHint()
                    }
                    self.reposition()
                }
            }.store(in: &observers)
            model.$expanded.dropFirst().sink { [weak self] _ in
                DispatchQueue.main.async { self?.reposition() }
            }.store(in: &observers)
            NotificationCenter.default.publisher(for: .guyiSettingsChanged).sink { [weak self] _ in
                guard let self else { return }
                self.engine.learning(self.preferences.settings.learnInput)
                self.language = self.preferences.inputLanguage
                self.resetLesson()
                self.startClipboardObservation()
                if self.active { self.refresh() }
            }.store(in: &observers)
            NotificationCenter.default.publisher(for: .guyiSelectionLanguagesChanged).sink { [weak self] _ in
                guard let self, self.model.clipboardMode else { return }
                self.model.enabledLanguages = self.preferences.settings.selectionLanguages ?? [.en, .id]
                self.translate(immediate: true)
            }.store(in: &observers)
        }
        model.language = language
        model.themeSettings = preferences.settings
        model.showPinyin = preferences.settings.showPinyin == true
        model.sentenceMode = preferences.settings.sentenceComposition == true
        model.selectedOutput = language
        model.enabledLanguages = preferences.settings.enabledLanguages ?? [.zh, .en, .id]
        AppDelegate.shared.currentController = self
        auditLifecycle("activate")
        startClipboardObservation()
    }

    override func deactivateServer(_ sender: Any!) {
        endSession()
    }

    private func endSession() {
        lastTranslationShortcutKey = nil
        TranslationSpeech.shared.stop()
        auditLifecycle("end")
        resetPunctuationContext()
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        pendingClipboard = nil
        observedSelection = nil
        observedSelectionText = nil
        if model.clipboardMode { clear(marked: false) }
        active = false
        clear(marked: false)
        panel?.orderOut(nil)
        if AppDelegate.shared.currentController === self { AppDelegate.shared.currentController = nil }
        sessionHostPID = nil
        eventClient = nil
    }

    override func inputControllerWillClose() {
        endSession()
        observers.removeAll()
        super.inputControllerWillClose()
    }

    override func recognizedEvents(_ sender: Any!) -> Int { Int(NSEvent.EventTypeMask.keyDown.rawValue) }

    override func setValue(_ value: Any!, forTag tag: Int, client sender: Any!) {
        guard tag == Int(kTextServiceInputModePropertyTag) else {
            super.setValue(value, forTag: tag, client: sender)
            return
        }
        guard let identifier = value as? String, identifier == "app.guyi.inputmethod.Guyi.pinyin" else { return }
        inputModeIdentifier = identifier
        if let sender = sender as? IMKTextInput { eventClient = sender }
        auditLifecycle("mode-set")
    }

    override func value(forTag tag: Int, client sender: Any!) -> Any! {
        if tag == Int(kTextServiceInputModePropertyTag) { return inputModeIdentifier as NSString }
        return super.value(forTag: tag, client: sender)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        if let sender = sender as? IMKTextInput { eventClient = sender }
        guard !bypassClient else { engine.learning(false); clear(marked: false); return false }
        guard let event, event.type == .keyDown else { return false }
        if !active || AppDelegate.shared.currentController !== self { activateServer(sender) }
        if sessionHostPID == nil { sessionHostPID = NSWorkspace.shared.frontmostApplication?.processIdentifier }
        guard ownsCurrentInputSource else { auditLifecycle("rejected-key-context"); return false }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 9, flags.contains(.command) {
            SelectionTranslationService.shared.notePaste()
            clipboardChange = NSPasteboard.general.changeCount
            pendingClipboard = nil
        }
        if !model.calculationExpression.isEmpty {
            if [36, 76].contains(event.keyCode), flags.intersection([.command, .control, .option]).isEmpty {
                guard let result = model.calculationResult else { NSSound.beep(); return true }
                insertCalculation(result)
                return true
            }
            clear(marked: false)
            if event.keyCode == 53 { return true }
        }
        let modifiers = ShortcutRecorder.carbonModifiers(flags)
        let shortcutAction = InputShortcuts.action(key: UInt32(event.keyCode), modifiers: modifiers,
                                                   settings: preferences.settings, hasCandidates: !engine.state().preedit.isEmpty)
        if shortcutAction.flatMap(InputShortcuts.translationLanguage) == nil { clearShortcutHint() }
        if let action = shortcutAction {
            if action.hasPrefix("copyContent") || action.hasPrefix("pasteContent"), let slot = action.last?.wholeNumberValue {
                useQuickContent(slot, paste: action.hasPrefix("paste")); return true
            }
            if let target = InputShortcuts.translationLanguage(action) {
                if event.isARepeat, lastTranslationShortcutKey == event.keyCode { return true }
                guard !model.original.isEmpty else { return false }
                lastTranslationShortcutKey = event.keyCode
                guard model.enabledLanguages.contains(target) else {
                    showQuickContentStatus(ShortcutMessages.text(.disabled)); return true
                }
                if model.translation.selectableText(for: target) != nil { clearShortcutHint(); insertTranslation(target) }
                else {
                    waitingShortcutLanguage = target
                    model.quickContentStatus = waitingShortcutMessage
                    reposition()
                    translate(immediate: true)
                }
                return true
            }
            switch action {
            case "emoji": showEmoji(); return true
            case "cycleLanguage", "cycleLanguageAlternate": cycleLanguage(); return true
            case "sentenceMode": preferences.toggleSentenceMode(); return true
            case "previousCandidates": turnPage(false); return true
            case "nextCandidates": turnPage(true); return true
            default: break
            }
        }
        lastTranslationShortcutKey = nil
        if flags.contains(.capsLock), language == .zh {
            resetPunctuationContext()
            if model.clipboardMode { clear(marked: false) }
            if !engine.rawInput.isEmpty || !draft.isEmpty { commitRawInput() }
            return false
        }
        if model.clipboardMode, ![36, 76, 53, 125, 126, 48].contains(event.keyCode),
           !(flags.contains(.option) && [18, 19, 20].contains(event.keyCode)) { clear(marked: false) }
        if flags.contains(.command) || flags.contains(.control) || flags.contains(.option) {
            if !model.original.isEmpty { commitOriginal() }
            resetPunctuationContext()
            return false
        }
        if literalToken != nil {
            if literalMouse != mouseDownCount { literalToken = nil }
            else if event.keyCode == 51 {
                literalToken?.removeLast()
                if literalToken?.isEmpty == true { literalToken = nil }
                if preferences.settings.sentenceComposition == true, !draft.isEmpty {
                    draft.removeLast()
                    sentenceNeedsConfirmation = true
                    refresh()
                    return true
                }
                previousCommittedCharacter = literalToken?.last
                return false
            } else if let text = event.characters, LiteralTokenPolicy.continues(text) {
                literalToken?.append(contentsOf: text)
                if preferences.settings.sentenceComposition == true {
                    draft += text
                    sentenceNeedsConfirmation = true
                    refresh()
                    return true
                }
                previousCommittedCharacter = text.last
                previousCommittedMouseCount = mouseDownCount
                return false
            } else { literalToken = nil }
        }
        if event.keyCode == 51, draft.isEmpty, engine.state().preedit.isEmpty,
           !numericExpression.isEmpty, previousCommittedMouseCount == mouseDownCount {
            numericExpression.removeLast()
            previousCommittedCharacter = numericExpression.last
            return false
        }
        if [36, 76, 48, 51, 53, 115, 116, 117, 119, 121, 123, 124, 125, 126].contains(event.keyCode) {
            resetPunctuationContext()
        }
        switch event.keyCode {
        case 53:
            guard !model.original.isEmpty || !draft.isEmpty else { return false }
            clear(marked: !model.clipboardMode); return true
        case 36, 76:
            guard !model.original.isEmpty else { return false }
            if flags.contains(.shift), language == .zh, !engine.rawInput.isEmpty { commitRawInput(); return true }
            if model.selectedOutput != model.language { insertTranslation(model.selectedOutput); return true }
            if model.clipboardMode { clear(marked: false); return false }
            if InputSafety.returnCommitsRaw(language: language, rawInput: engine.rawInput,
                                           selectedTranslation: false, clipboard: false) { commitRawInput(); return true }
            if preferences.settings.sentenceComposition == true {
                if sentenceNeedsConfirmation {
                    sentenceNeedsConfirmation = false
                    refresh()
                    return true
                }
                commitOriginal()
                return true
            }
            if !model.candidates.isEmpty { choose(model.selected); return true }
            commitOriginal(); return true
        case 48:
            guard !model.original.isEmpty else { return false }
            if model.clipboardMode { clear(marked: false) }
            else { commitOriginal() }
            return false
        case 51:
            if !engine.state().preedit.isEmpty { _ = engine.key(0xff08) }
            else if !draft.isEmpty { draft.removeLast() }
            else { return false }
            refresh(); return true
        case 125, 126:
            guard !model.original.isEmpty else { return false }
            if model.selectedOutput == model.language, !model.candidates.isEmpty {
                if event.keyCode == 125 { turnPage(true); return true }
                if model.hasPreviousCandidates { turnPage(false); return true }
            }
            let choices = [model.language] + Language.targets.filter { $0 != model.language && model.enabledLanguages.contains($0) }
            let index = choices.firstIndex(of: model.selectedOutput) ?? 0
            model.selectedOutput = choices[min(choices.count - 1, max(0, index + (event.keyCode == 126 ? 1 : -1)))]
            return true
        case 123, 124:
            if !model.candidates.isEmpty {
                guard model.selectedOutput == language else { return true }
                let next = model.selected + (event.keyCode == 124 ? 1 : -1)
                guard model.candidates.indices.contains(next) else { return true }
                model.selectedOutput = language
                moveCandidate(forward: event.keyCode == 124)
                return true
            }
            if !draft.isEmpty { commitOriginal() }
            return false
        case 116, 121:
            guard !engine.state().preedit.isEmpty else { return false }
            turnPage(event.keyCode == 121); return true
        default: break
        }
        if event.characters == " ", InputSafety.spaceCommitsSentence(language: language,
            sentenceMode: preferences.settings.sentenceComposition == true,
            hasPreedit: !engine.state().preedit.isEmpty, draft: draft) {
            commitOriginal()
            return true
        }
        guard let characters = event.characters, !characters.isEmpty,
              !characters.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return false }
        let raw = engine.rawInput
        let pendingLatin = raw.isEmpty ? LiteralTokenPolicy.latinWord(draft) : raw
        let precedingLatin = previousCommittedMouseCount == mouseDownCount && draft.isEmpty ? previousLatinWord : ""
        let selected = raw.isEmpty ? pendingLatin : (model.candidates.indices.contains(model.selected) ? model.candidates[model.selected] : nil)
        if LiteralTokenPolicy.begins(raw: pendingLatin, selected: selected, precedingLatin: precedingLatin, punctuation: characters) {
            let text = draft + raw + characters
            engine.clear()
            if preferences.settings.sentenceComposition == true {
                draft = text
                sentenceNeedsConfirmation = true
                refresh()
            } else {
                inputClient?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                rememberCommittedText(text)
                clear(marked: false)
            }
            literalToken = precedingLatin + pendingLatin + characters
            literalMouse = mouseDownCount
            return true
        }
        if previousCommittedMouseCount != mouseDownCount { numericExpression = ""; numericExpressionTooLong = false }
        if characters == "=", numericExpression.contains(where: { $0.isNumber }), draft.isEmpty, engine.state().preedit.isEmpty {
            showCalculation(numericExpression)
            return true
        }
        if InputSafety.insertsWithoutComposition(characters, hasComposition: !draft.isEmpty || !engine.state().preedit.isEmpty) {
            lastChosenPhrase = nil
            let text = language == .zh ? ChinesePunctuation.convert(characters, preceding: precedingClientCharacter()) : characters
            inputClient?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
            rememberCommittedText(text)
            if Calculator.accepts(text) {
                if numericExpression.count + text.count <= 256, !numericExpressionTooLong { numericExpression += text }
                else { numericExpressionTooLong = true }
            } else { numericExpression = ""; numericExpressionTooLong = false }
            return true
        }
        numericExpression = ""
        numericExpressionTooLong = false
        guard draft.count + engine.state().preedit.count < 4_000 else { NSSound.beep(); return true }
        if language == .zh {
            guard engine.available else { model.translation.invalidate(message: Localizer.format("拼音引擎未就绪，请重新安装%@。", Brand.name)); reposition(); return false }
            let current = engine.state()
            if !current.preedit.isEmpty, characters == " " { choose(model.selected); return true }
            if !current.preedit.isEmpty, let number = Int(characters), (1...5).contains(number) {
                let index = model.visibleCandidates.lowerBound + number - 1
                if model.visibleCandidates.contains(index) { choose(index) }
                return true
            }
            if let scalar = characters.unicodeScalars.first, characters.unicodeScalars.count == 1,
               (CharacterSet.lowercaseLetters.contains(scalar) && scalar.isASCII || characters == "'") {
                _ = engine.key(Int32(scalar.value))
                draft += engine.commit()
            } else {
                settlePinyin()
                let preceding = draft.last ?? precedingClientCharacter()
                draft += ChinesePunctuation.convert(characters, preceding: preceding)
                if preferences.settings.sentenceComposition != true { commitOriginal(); return true }
            }
        } else {
            draft += characters
            if preferences.settings.sentenceComposition == true { sentenceNeedsConfirmation = true }
            if preferences.settings.sentenceComposition != true, characters == " " { commitOriginal(); return true }
        }
        refresh()
        if preferences.settings.sentenceComposition == true, SentenceBoundary.endsSentence(draft) {
            translate(immediate: true)
        }
        return true
    }

    override func commitComposition(_ sender: Any!) { commitOriginal() }

    override func hidePalettes() {
        panel?.orderOut(nil)
        super.hidePalettes()
    }

    override func menu() -> NSMenu! {
        let menu = NSMenu()
        let setting = NSMenuItem(title: Brand.settings + "…", action: #selector(openSettings(_:)), keyEquivalent: "")
        setting.target = self
        menu.addItem(setting)
        let mode = NSMenuItem(title: Localizer.text("切换原文语言"), action: #selector(switchLanguage(_:)), keyEquivalent: "")
        mode.target = self
        menu.addItem(mode)
        let emoji = NSMenuItem(title: Localizer.text("表情与符号"), action: #selector(openEmoji(_:)), keyEquivalent: "")
        emoji.target = self
        menu.addItem(emoji)
        return menu
    }
    @objc private func openSettings(_ sender: Any?) { AppDelegate.shared.showSettings() }
    @objc private func switchLanguage(_ sender: Any?) { cycleLanguage() }
    @objc private func openEmoji(_ sender: Any?) { showEmoji() }
    private func showEmoji() {
        if model.clipboardMode { clear(marked: false) } else { commitOriginal() }
        NSApp.orderFrontCharacterPalette(nil)
    }

    private func cycleLanguage() {
        commitOriginal()
        language = language == .zh ? .en : (language == .en ? .id : .zh)
        preferences.inputLanguage = language
        model.language = language
        model.selectedOutput = language
        model.translation.invalidate(message: "已切换到 \(language.title) · 开始输入")
        reposition(showEmpty: true)
    }
    private func choose(_ index: Int) {
        guard model.candidates.indices.contains(index) else { return }
        let code = engine.rawInput
        if index < model.candidates.count, hotwordCandidates.contains(model.candidates[index]) {
            let chosen = model.candidates[index]
            draft += chosen
            learnChosenPhrase(code, text: chosen)
            engine.clear()
            if preferences.settings.sentenceComposition != true { commitOriginal() } else { refresh() }
            return
        }
        guard active, candidateEngineIndices.indices.contains(index), let engineIndex = candidateEngineIndices[index] else { return }
        engine.select(engineIndex)
        let committed = engine.commit()
        draft += committed
        if !committed.isEmpty { learnChosenPhrase(code, text: committed) }
        if preferences.settings.sentenceComposition != true, engine.state().preedit.isEmpty {
            commitOriginal()
            return
        }
        refresh()
    }
    private func turnPage(_ forward: Bool) {
        let groups = model.candidateGroups
        if let group = groups.firstIndex(where: { $0.contains(model.candidateStart) }) {
            let next = group + (forward ? 1 : -1)
            if groups.indices.contains(next) {
                let index = groups[next].lowerBound
                if candidateEngineIndices.indices.contains(index), let engineIndex = candidateEngineIndices[index] { engine.highlight(engineIndex); refresh() }
                model.selected = index
                model.candidateStart = index
                model.selectedOutput = language
                if hotwordCandidates.contains(model.candidates[index]) {
                    model.original = draft + model.candidates[index]
                    translate(immediate: false)
                }
                return
            }
        }
        guard forward ? !engine.lastPage : engine.page > 0 else { return }
        _ = engine.key(forward ? 0xff56 : 0xff55)
        refresh()
        let index = forward ? 0 : (model.candidateGroups.last?.lowerBound ?? 0)
        if candidateEngineIndices.indices.contains(index), let engineIndex = candidateEngineIndices[index] {
            engine.highlight(engineIndex)
            refresh()
        }
        model.selected = index
        model.revealSelectedCandidate()
    }
    private func moveCandidate(forward: Bool) {
        var next = model.selected + (forward ? 1 : -1)
        if next >= model.candidates.count || next < 0 {
            guard forward ? !engine.lastPage : engine.page > 0 else { return }
            turnPage(forward)
            next = forward ? 0 : max(0, model.candidates.count - 1)
        }
        guard model.candidates.indices.contains(next) else { return }
        if candidateEngineIndices.indices.contains(next), let engineIndex = candidateEngineIndices[next] {
            engine.highlight(engineIndex)
            refresh()
        }
        model.selected = next
        model.revealSelectedCandidate()
        model.selectedOutput = language
        if hotwordCandidates.contains(model.candidates[next]) {
            model.original = draft + model.candidates[next]
            translate(immediate: false)
        }
    }
    private func settlePinyin() {
        let state = engine.state()
        if !state.preedit.isEmpty {
            if model.candidates.indices.contains(model.selected), hotwordCandidates.contains(model.candidates[model.selected]) {
                let chosen = model.candidates[model.selected]
                learnChosenPhrase(engine.rawInput, text: chosen)
                engine.clear()
                draft += chosen
            } else {
                let committed = engine.finish()
                draft += committed.isEmpty ? state.preview : committed
            }
        }
    }
    private func refresh() {
        model.themeSettings = preferences.settings
        guard !bypassClient else { clear(marked: false); return }
        guard active, ownsCurrentInputSource else { clear(marked: false); return }
        if !model.calculationExpression.isEmpty { reposition(); return }
        model.showPinyin = preferences.settings.showPinyin == true
        model.sentenceMode = preferences.settings.sentenceComposition == true
        model.awaitingConfirmation = model.sentenceMode && sentenceNeedsConfirmation
        if model.clipboardMode {
            model.enabledLanguages = preferences.settings.selectionLanguages ?? [.en, .id]
            if preferences.settings.translateClipboard == false && preferences.settings.translateSelection == false { clear(marked: false) }
            else { translate(immediate: true) }
            return
        }
        updateCaret()
        resetLesson()
        model.selectedOutput = language
        model.enabledLanguages = preferences.settings.enabledLanguages ?? [.zh, .en, .id]
        let state = engine.state()
        model.preedit = state.preedit
        model.candidates = state.candidates
        candidateEngineIndices = state.candidates.indices.map { Optional($0) }
        model.page = engine.page
        model.lastPage = engine.lastPage
        hotwordCandidates = []
        if preferences.settings.hotwordsEnabled != false, language == .zh {
            let matches = HotwordStore.shared.matches(state.preedit).filter { !state.candidates.contains($0) }
            if let hotword = matches.first {
                model.candidates = Array(state.candidates.prefix(4)) + [hotword]
                candidateEngineIndices = Array(state.candidates.indices.prefix(4)).map { Optional($0) } + [nil]
                hotwordCandidates.insert(hotword)
            }
        }
        if preferences.settings.learnInput, language == .zh, engine.page == 0 {
            let learned = UserPhraseStore.shared.matches(state.preedit)
            for text in learned.reversed() {
                if let index = model.candidates.firstIndex(of: text) { model.candidates.remove(at: index);candidateEngineIndices.remove(at: index) }
                model.candidates.insert(text, at: 0);candidateEngineIndices.insert(nil, at: 0);hotwordCandidates.insert(text)
            }
        }
        if language == .zh, engine.page == 0, preferences.settings.emojiCandidates != false {
            let emoji = EmojiCandidates.matches(state.preedit).filter { !model.candidates.contains($0) }
            let start = min(2, model.candidates.count)
            for (offset, text) in emoji.enumerated() {
                model.candidates.insert(text, at: start + offset)
                candidateEngineIndices.insert(nil, at: start + offset)
                hotwordCandidates.insert(text)
            }
        }
        if language == .zh, engine.page == 0, let english = MixedInputCandidates.preferredEnglish(engine.rawInput) {
            if let index = model.candidates.firstIndex(of: english) {
                model.candidates.remove(at: index); candidateEngineIndices.remove(at: index)
            }
            model.candidates.insert(english, at: 0); candidateEngineIndices.insert(nil, at: 0)
            hotwordCandidates.insert(english)
        }
        model.selected = candidateEngineIndices.firstIndex(where: { $0 == state.selected }) ?? 0
        if !candidateEngineIndices.isEmpty, candidateEngineIndices[0] == nil, state.selected == 0 { model.selected = 0 }
        model.revealSelectedCandidate()
        model.original = draft + (model.candidates.indices.contains(model.selected) && hotwordCandidates.contains(model.candidates[model.selected]) ? model.candidates[model.selected] : (state.preview.isEmpty ? state.preedit : state.preview))
        model.language = language
        let marked = draft + state.preedit
        inlineCursor = draft.utf16.count + engine.cursor(in: state.preedit)
        let attributed = NSMutableAttributedString(string: marked)
        let range = NSRange(location: 0, length: marked.utf16.count)
        if let attributes = mark(forStyle: kTSMHiliteSelectedRawText, at: range) as? [NSAttributedString.Key: Any] {
            attributed.setAttributes(attributes, range: range)
        }
        inputClient?.setMarkedText(attributed, selectionRange: NSRange(location: inlineCursor, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        updateCaret()
        caretUpdateTask?.cancel()
        caretUpdateTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(16)) } catch { return }
            guard let self, self.active, !self.model.original.isEmpty,
                  self.ownsCurrentInputSource else { return }
            self.updateCaret()
            self.reposition()
        }
        translate(immediate: false)
        reposition()
    }
    private func translate(immediate: Bool) {
        guard !bypassClient else { model.translation.invalidate(); return }
        var settings = preferences.settings
        settings.source = model.clipboardMode ? .auto : language
        if model.clipboardMode { settings.enabledLanguages = model.enabledLanguages; settings.translateWholeSelection = true }
        model.translation.update(text: model.original, composing: false, settings: settings, apiKey: preferences.apiKey, immediate: immediate)
    }
    private func clearShortcutHint() {
        guard waitingShortcutLanguage != nil else { return }
        waitingShortcutLanguage = nil
        if model.quickContentStatus == waitingShortcutMessage { model.quickContentStatus = "" }
    }
    private func insertTranslation(_ language: Language) {
        guard !bypassClient, active, ownsCurrentInputSource else { return }
        guard active, model.enabledLanguages.contains(language), let translated = model.translation.selectableText(for: language), !translated.isEmpty,
              model.translation.currentText == model.original else { NSSound.beep(); return }
        let text = InsertionText.singleLine(translated)
        _ = engine.finish()
        inputClient?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        rememberCommittedText(text)
        clear(marked: false)
    }
    private func copyPanelText(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else { return }
        clipboardChange = pasteboard.changeCount
        pendingClipboard = nil
        clipboardMouseCount = mouseDownCount
        model.copiedText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            if self?.model.copiedText == text { self?.model.copiedText = "" }
        }
    }
    private func commitOriginal() {
        guard !bypassClient, active, ownsCurrentInputSource else { clear(marked: false); return }
        settlePinyin()
        let original = draft
        if !original.isEmpty {
            inputClient?.insertText(InsertionText.singleLine(original), replacementRange: NSRange(location: NSNotFound, length: 0))
            rememberCommittedText(original)
        }
        clear(marked: false)
    }
    private func commitRawInput() {
        lastChosenPhrase = nil
        guard active, ownsCurrentInputSource else { clear(marked: false); return }
        guard !bypassClient else { clear(marked: false); return }
        let text = draft + engine.rawInput
        guard !text.isEmpty else { return }
        inputClient?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        rememberCommittedText(text)
        clear(marked: false)
    }
    private func clear(marked: Bool = true) {
        clearShortcutHint()
        literalToken = nil; literalMouse = nil
        model.quickContentStatus = ""
        caretUpdateTask?.cancel()
        caretUpdateTask = nil
        compositionRect = .zero
        model.clipboardMode = false
        clipboardAnchor = nil
        clipboardMouseCount = nil
        model.calculationExpression = ""
        model.calculationResult = nil
        model.calculationError = ""
        numericExpression = ""
        numericExpressionTooLong = false
        engine.clear()
        draft = ""
        sentenceNeedsConfirmation = false
        model.awaitingConfirmation = false
        inlineCursor = 0
        caret = .zero
        model.original = ""
        model.preedit = ""
        model.candidates = []
        model.translation.invalidate()
        resetLesson()
        if marked && !bypassClient && active && ownsCurrentInputSource { inputClient?.setMarkedText(NSAttributedString(string: ""), selectionRange: NSRange(location: 0, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0)) }
        panel?.orderOut(nil)
    }
    private func reposition(showEmpty: Bool = false) {
        guard ownsCurrentInputSource else {
            panel?.orderOut(nil)
            return
        }
        guard !ScreenshotService.shared.capturing else { panel?.orderOut(nil); return }
        guard active, showEmpty || !model.original.isEmpty else { panel?.orderOut(nil); return }
        if panel == nil { panel = CandidatePanel(model: model) }
        if caret == .zero { updateCaret() }
        panel?.present(near: caret, avoiding: compositionRect == .zero ? nil : compositionRect)
    }
    func prepareExternalSourceSwitch() { if ownsCurrentInputSource { commitOriginal() } }
    func hideCandidatePanel() { panel?.orderOut(nil) }
    func hideIfClientInactive() {
        if sessionHostPID != NSWorkspace.shared.frontmostApplication?.processIdentifier {
            panel?.orderOut(nil)
            model.translation.invalidate()
            resetLesson()
        }
    }
    private func updateCaret() {
        guard !bypassClient else { return }
        guard let client = inputClient else { return }
        if model.clipboardMode, let clipboardAnchor {
            caret = clipboardAnchor
            compositionRect = clipboardAnchor
            return
        }
        let clicks = mouseDownCount
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let origin = windows.first(where: { $0[kCGWindowOwnerPID as String] as? pid_t == sessionHostPID && $0[kCGWindowLayer as String] as? Int == 0 })
            .flatMap { $0[kCGWindowBounds as String] as? [String: Any] }
            .flatMap { CGRect(dictionaryRepresentation: $0 as CFDictionary)?.origin }
        if caretMouseCount != clicks || caretWindowOrigin != origin { caret = .zero; compositionRect = .zero }
        caretMouseCount = clicks
        caretWindowOrigin = origin
        if ["com.googlecode.iterm2", "com.apple.Terminal"].contains(client.bundleIdentifier() ?? "") {
            var line = NSRect.zero
            _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &line)
            if CandidatePlacement.validCaret(line), NSScreen.screens.contains(where: { $0.frame.intersects(line) }) {
                storeCaret(line)
                compositionRect = line
                return
            }
        }
        let markedRange = client.markedRange()
        let selectedRange = client.selectedRange()
        if UserDefaults.standard.bool(forKey: "diagnoseCandidateGeometry") {
            var legacyRect = NSRect.zero
            _ = client.attributes(forCharacterIndex: inlineCursor, lineHeightRectangle: &legacyRect)
            var actual = NSRange(location: NSNotFound, length: 0)
            let firstRect = client.firstRect(forCharacterRange: NSRange(location: selectedRange.location, length: 0), actualRange: &actual)
            Logger(subsystem: "app.guyi.inputmethod.Guyi", category: "CandidateGeometry").notice("caret selected=\(selectedRange.location), marked=\(markedRange.location):\(markedRange.length), cursor=\(self.inlineCursor), first=\(NSStringFromRect(firstRect), privacy: .public), legacy=\(NSStringFromRect(legacyRect), privacy: .public)")
        }
        let documentLocation = selectedRange.location != NSNotFound ? selectedRange.location :
            (markedRange.location != NSNotFound ? markedRange.location + min(inlineCursor, markedRange.length) : NSNotFound)
        if documentLocation != NSNotFound {
            var actual = NSRange(location: NSNotFound, length: 0)
            let primary = client.firstRect(forCharacterRange: NSRange(location: documentLocation, length: 0), actualRange: &actual)
            var legacy = NSRect.zero
            _ = client.attributes(forCharacterIndex: inlineCursor, lineHeightRectangle: &legacy)
            caretGeometry.calibrate(primary: primary, legacy: legacy)
            let rect = caretGeometry.adjusted(primary)
            if CandidatePlacement.validCaret(rect),
               NSScreen.screens.contains(where: { $0.frame.intersects(rect.insetBy(dx: -1, dy: -1)) }) {
                storeCaret(rect)
                compositionRect = rect
                if markedRange.location != NSNotFound, markedRange.length > 0 {
                    var firstActual = NSRange(location: NSNotFound, length: 0)
                    let first = caretGeometry.adjusted(client.firstRect(forCharacterRange: NSRange(location: markedRange.location, length: 0), actualRange: &firstActual))
                    if CandidatePlacement.validCaret(first),
                       NSScreen.screens.contains(where: { $0.frame.intersects(first.insetBy(dx: -1, dy: -1)) }) {
                        compositionRect = rect.union(first)
                    }
                    var lastActual = NSRange(location: NSNotFound, length: 0)
                    let last = caretGeometry.adjusted(client.firstRect(forCharacterRange: NSRange(location: markedRange.location + markedRange.length, length: 0), actualRange: &lastActual))
                    if CandidatePlacement.validCaret(last),
                       NSScreen.screens.contains(where: { $0.frame.intersects(last.insetBy(dx: -1, dy: -1)) }) {
                        compositionRect = compositionRect.union(last)
                    }
                }
                return
            }
        }
        for index in [inlineCursor, 0, NSNotFound] {
            var rect = NSRect.zero
            _ = client.attributes(forCharacterIndex: index, lineHeightRectangle: &rect)
            if CandidatePlacement.validCaret(rect),
               NSScreen.screens.contains(where: { $0.frame.intersects(rect.insetBy(dx: -1, dy: -1)) }) {
                storeCaret(rect)
                compositionRect = rect
                return
            }
        }
    }
    private func storeCaret(_ rect: NSRect) {
        if caret != .zero, abs(caret.minY - rect.minY) < 2,
           abs(caret.height - rect.height) < 2,
           abs(caret.minX - rect.minX) < 48 {
            caret = NSRect(x: caret.minX, y: rect.minY, width: rect.width, height: rect.height)
        } else { caret = rect }
    }
    private func resetLesson() {
        grammarRevision += 1
        grammarTask?.cancel()
        model.lesson = nil
        model.lessonStatus = ""
    }
    private func resetPunctuationContext() {
        literalToken = nil; literalMouse = nil; previousLatinWord = ""
        lastChosenPhrase = nil
        previousCommittedCharacter = nil
        previousCommittedMouseCount = nil
        numericExpression = ""
        numericExpressionTooLong = false
    }
    private func learnChosenPhrase(_ code: String, text: String) {
        guard preferences.settings.learnInput, language == .zh, !IsSecureEventInputEnabled() else { lastChosenPhrase = nil; return }
        let normalized = LearnedPhrases.normalized(code)
        guard LearnedPhrases.valid(normalized, text: text) else { lastChosenPhrase = nil; return }
        UserPhraseStore.shared.record(normalized, text: text)
        let now = Date(), clicks = mouseDownCount
        if let previous = lastChosenPhrase, previous.clicks == clicks, now.timeIntervalSince(previous.time) < 8,
           LearnedPhrases.valid(previous.code + normalized, text: previous.text + text) {
            UserPhraseStore.shared.record(previous.code + normalized, text: previous.text + text)
        }
        lastChosenPhrase = (normalized, text, now, clicks)
    }
    private func showCalculation(_ expression: String) {
        let tooLong = numericExpressionTooLong
        inputClient?.insertText("=", replacementRange: NSRange(location: NSNotFound, length: 0))
        rememberCommittedText("=")
        numericExpression = ""
        numericExpressionTooLong = false
        model.translation.invalidate()
        model.original = expression + "="
        model.calculationExpression = model.original
        do {
            if tooLong { throw Calculator.Failure.tooLong }
            model.calculationResult = try Calculator.evaluate(expression)
        }
        catch {
            switch error as? Calculator.Failure {
            case .divisionByZero: model.calculationError = Localizer.text("不能除以零")
            case .overflow, .tooLong: model.calculationError = Localizer.text("超出精确计算范围")
            case .exponent: model.calculationError = Localizer.text("仅支持 −12 到 12 的整数次幂")
            default: model.calculationError = Localizer.text("请检查公式和数字分组")
            }
        }
        model.confirmCalculation = { [weak self] in
            guard let self, let result = self.model.calculationResult else { return }
            self.insertCalculation(result)
        }
        updateCaret()
        reposition()
    }
    private func insertCalculation(_ result: String) {
        guard active, ownsCurrentInputSource else { return }
        inputClient?.insertText(result, replacementRange: NSRange(location: NSNotFound, length: 0))
        rememberCommittedText(result)
        clear(marked: false)
    }
    private func rememberCommittedText(_ text: String) {
        if !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isLetter }) {
            previousLatinWord = (previousCommittedMouseCount == mouseDownCount ? previousLatinWord : "") + text
            if previousLatinWord.count > 253 { previousLatinWord = String(previousLatinWord.suffix(253)) }
        } else { previousLatinWord = "" }
        previousCommittedCharacter = text.last
        previousCommittedMouseCount = mouseDownCount
    }
    private func precedingClientCharacter() -> Character? {
        guard let client = inputClient, active, ownsCurrentInputSource else { return nil }
        if previousCommittedMouseCount == mouseDownCount, let previousCommittedCharacter {
            return previousCommittedCharacter
        }
        let selection = client.selectedRange()
        guard selection.length == 0 else { return nil }
        if selection.location != NSNotFound {
            if selection.location > 0 {
                let range = NSRange(location: selection.location - 1, length: 1)
                var actual = NSRange(location: NSNotFound, length: 0)
                if let text = client.string(from: range, actualRange: &actual), actual == range, !text.isEmpty { return text.last }
            } else if !["com.googlecode.iterm2", "com.apple.Terminal"].contains(client.bundleIdentifier() ?? "") {
                return nil
            }
        }
        // Terminals may expose no surrounding text and update their caret only after
        // insertText returns. Preserve our uninterrupted input, not a stale caret.
        // Navigation, shortcuts, activation and pointer clicks invalidate this fallback.
        guard previousCommittedMouseCount == mouseDownCount else { return nil }
        return previousCommittedCharacter
    }
    private func toggleLanguage(_ language: Language) {
        if model.clipboardMode {
            var selected = preferences.settings.selectionLanguages ?? [.en, .id]
            if selected.contains(language) { selected.removeAll { $0 == language } } else { selected.append(language) }
            preferences.saveSelectionLanguages(selected)
            return
        }
        var settings = preferences.settings
        var enabled = settings.enabledLanguages ?? [.zh, .en, .id]
        if enabled.contains(language) { enabled.removeAll { $0 == language } }
        else { enabled.append(language) }
        settings.enabledLanguages = enabled
        Task { @MainActor in
            do { try await preferences.save(settings, key: preferences.apiKey) }
            catch { model.translation.invalidate(message: error.localizedDescription) }
        }
    }
    private func startClipboardObservation() {
        clipboardTimer?.invalidate()
        clipboardTimer = nil
        pendingClipboard = nil
        observedSelection = nil
        observedSelectionText = nil
        guard active, !bypassClient, preferences.settings.translateClipboard != false || preferences.settings.translateSelection != false else { return }
        clipboardChange = NSPasteboard.general.changeCount
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkClipboard() }
        }
    }
    private func checkClipboard() {
        // Selection outside editable text belongs to the app-wide AX service.
        // Avoid duplicate popovers where the host exposes AX selection as well.
        if AXIsProcessTrusted() || SelectionTranslationService.shared.isShowing { return }
        guard model.calculationExpression.isEmpty else { return }
        guard ownsCurrentInputSource, !IsSecureEventInputEnabled(),
              let bundle = inputClient?.bundleIdentifier(), bundle != Bundle.main.bundleIdentifier,
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundle else { return }
        let pasteboard = NSPasteboard.general
        guard !TranslationPrivacy.protectedContext(), !TranslationPrivacy.protectedClipboard(pasteboard) else {
            clipboardChange = pasteboard.changeCount; pendingClipboard = nil
            if model.clipboardMode { clear(marked: false) }
            return
        }
        guard draft.isEmpty, engine.state().preedit.isEmpty else {
            clipboardChange = pasteboard.changeCount
            pendingClipboard = nil
            return
        }
        let selection = inputClient?.selectedRange() ?? NSRange(location: NSNotFound, length: 0)
        if SelectionTranslationService.shared.suppressingAutomaticTranslation {
            clipboardChange = pasteboard.changeCount
            pendingClipboard = nil
            observedSelection = selection
            var actual = NSRange(location: NSNotFound, length: 0)
            observedSelectionText = selection.length > 0 ? inputClient?.string(from: selection, actualRange: &actual) : nil
            return
        }
        var selectedText: String?
        if preferences.settings.translateSelection != false, selection.location != NSNotFound, selection.length > 0, selection.length <= 16_000 {
            var actual = NSRange(location: NSNotFound, length: 0)
            if let value = inputClient?.string(from: selection, actualRange: &actual), actual == selection,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 4_000 {
                selectedText = value
            }
        }
        if model.clipboardMode, clipboardMouseCount != mouseDownCount,
           panel?.frame.contains(NSEvent.mouseLocation) != true {
            clear(marked: false)
            observedSelection = selection
            observedSelectionText = selectedText
            clipboardChange = pasteboard.changeCount
            pendingClipboard = nil
            return
        }
        if observedSelection != selection || observedSelectionText != selectedText {
            observedSelection = selection
            observedSelectionText = selectedText
            pendingClipboard = nil
            if model.clipboardMode { clear(marked: false) }
            if let selectedText {
                if preferences.settings.copySelectionAutomatically == true {
                    pasteboard.clearContents(); pasteboard.setString(selectedText, forType: .string)
                }
                pendingClipboard = selectedText
                clipboardChange = pasteboard.changeCount
            }
        }
        if preferences.settings.translateClipboard != false, pasteboard.changeCount != clipboardChange {
            clipboardChange = pasteboard.changeCount
            if model.clipboardMode { clear(marked: false) }
            if let value = pasteboard.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, value.count <= 4_000 {
                pendingClipboard = selectedText ?? value
            } else { pendingClipboard = nil }
        }
        guard draft.isEmpty, engine.state().preedit.isEmpty, let value = pendingClipboard else { return }
        pendingClipboard = nil
        guard SelectionTranslationPolicy.shouldTranslate(value, settings: preferences.settings, interfaceLanguage: InterfaceLanguage.shared.code),
              !(preferences.settings.selectionLanguages ?? [.en, .id]).isEmpty else { return }
        caret = .zero
        resetLesson()
        model.clipboardMode = true
        clipboardMouseCount = mouseDownCount
        let pointer = NSEvent.mouseLocation
        clipboardAnchor = NSRect(x: pointer.x, y: pointer.y - 9, width: 1, height: 18)
        // Prefer the host's real selection bounds. Terminals can report their
        // insertion cursor for this query, far away from the selected output.
        if selection.location != NSNotFound, selection.length > 0,
           !["com.googlecode.iterm2", "com.apple.Terminal"].contains(inputClient?.bundleIdentifier() ?? "") {
            var actual = NSRange(location: NSNotFound, length: 0)
            if let rect = inputClient?.firstRect(forCharacterRange: selection, actualRange: &actual),
               CandidatePlacement.validCaret(rect), NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) {
                clipboardAnchor = rect
            }
        }
        model.original = value
        model.preedit = ""
        model.candidates = []
        model.language = SelectionTranslationPolicy.detectedLanguage(value)
        model.selectedOutput = language
        model.enabledLanguages = preferences.settings.selectionLanguages ?? [.en, .id]
        translate(immediate: true)
        reposition()
    }
    private func learn(_ language: Language) {
        guard let result = model.translation.result, !result.text(for: language).isEmpty else { return }
        resetLesson()
        let revision = grammarRevision
        let original = model.original
        model.lessonStatus = "正在整理语法说明…"
        model.lessonLanguage = language
        let settings = preferences.settings
        let key = preferences.apiKey
        grammarTask = Task { @MainActor [weak self] in
            do {
                let lesson = try await GrammarTeacher().explain(original: original, translation: result.text(for: language), language: language, settings: settings, apiKey: key)
                guard let self, !Task.isCancelled, revision == self.grammarRevision, self.active else { return }
                self.model.lesson = lesson
            } catch {
                guard let self, !Task.isCancelled, revision == self.grammarRevision else { return }
                self.model.lessonStatus = error.localizedDescription
            }
        }
    }

    private func useQuickContent(_ slot: Int, paste: Bool) {
        do {
            guard let entry = QuickContentStore.shared.entry(slot) else { throw QuickContentError.missing }
            if paste, !model.original.isEmpty || !draft.isEmpty || !engine.rawInput.isEmpty {
                showQuickContentStatus(Localizer.text("请先确认或取消当前输入，再粘贴常用内容。"))
                return
            }
            if paste, entry.kind == .text, let text = entry.text {
                let terminal = ["com.googlecode.iterm2", "com.apple.Terminal"].contains(inputClient?.bundleIdentifier() ?? "")
                if !terminal || text == InsertionText.singleLine(text) {
                    guard text.utf8.count <= 65_536, ownsCurrentInputSource else { throw QuickContentError.invalid }
                    inputClient?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
                    showQuickContentStatus(Localizer.text("已插入常用文字。"))
                    return
                }
            }
            try QuickContentStore.shared.copy(slot)
            clipboardChange = NSPasteboard.general.changeCount
            let target = NSWorkspace.shared.frontmostApplication
            let terminal = ["com.googlecode.iterm2", "com.apple.Terminal"].contains(target?.bundleIdentifier ?? "")
            if paste, !terminal, !IsSecureEventInputEnabled(), CGPreflightPostEventAccess(), let target,
               target.bundleIdentifier == inputClient?.bundleIdentifier(), ownsCurrentInputSource {
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 9, keyDown: down)
                    event?.flags = .maskCommand
                    event?.postToPid(target.processIdentifier)
                }
                showQuickContentStatus(Localizer.text("已请求粘贴；目标应用需支持此内容类型。"))
            } else { showQuickContentStatus(Localizer.text("已复制，可在目标应用粘贴。")) }
        } catch { showQuickContentStatus(error.localizedDescription) }
    }

    private func showQuickContentStatus(_ message: String) {
        model.quickContentStatus = message
        reposition(showEmpty: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, self.model.quickContentStatus == message else { return }
            self.model.quickContentStatus = ""
            if self.model.original.isEmpty { self.panel?.orderOut(nil) }
        }
    }

    private func auditLifecycle(_ stage: String) {
        guard UserDefaults.standard.bool(forKey: "diagnoseInputLifecycle") else { return }
        let foreground = NSWorkspace.shared.frontmostApplication
        let clientBundle = stage == "activate" ? (inputClient?.bundleIdentifier() ?? "unavailable") : "not-queried"
        let foregroundBundle = foreground?.bundleIdentifier ?? "unavailable"
        let current = AppDelegate.shared.currentController === self
        Logger(subsystem: "app.guyi.inputmethod.Guyi", category: "InputLifecycle").notice(
            "stage=\(stage, privacy: .public) active=\(self.active) current=\(current) hostPID=\(self.sessionHostPID ?? -1) foregroundPID=\(foreground?.processIdentifier ?? -1) clientBundle=\(clientBundle, privacy: .public) foregroundBundle=\(foregroundBundle, privacy: .public)")
    }
}
