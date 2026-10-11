import AppKit
import GuyiCore

struct LayoutTranslator: StreamingTranslating {
    func translate(_ text: String, settings: TranslationSettings, apiKey: String) async throws -> GuyiCore.Translation {
        GuyiCore.Translation(source: .zh, zh: text, en: String(repeating: "A complete sentence for layout testing. ", count: 8),
                    id: String(repeating: "Kalimat lengkap untuk pengujian. ", count: 8), note: "这是一段用于验证说明文字不会撑高候选框的长说明。")
    }
    func stream(_ text: String, settings: TranslationSettings, apiKey: String,
                progress: @escaping @Sendable ([String: String]) async -> Void) async throws -> GuyiCore.Translation {
        let value = try await translate(text, settings: settings, apiKey: apiKey)
        for length in [8, 40, 100, 200] {
            await progress(["en": String(value.en.prefix(length)), "id": String(value.id.prefix(length))])
            try await Task.sleep(for: .milliseconds(100))
        }
        return value
    }
}

@main
struct PanelLayoutSmoke {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let session = TranslationSession(translator: LayoutTranslator(), cache: TranslationCache())
        let suite = "app.guyi.panel-layout-smoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = CandidateModel(translation: session, defaults: defaults)
        model.candidates = ["我在输入很多", "我在", "我再", "窝在", "卧在"]
        let groups = model.candidateGroups
        precondition(groups.flatMap { Array($0) } == Array(model.candidates.indices), "Fitted pages do not skip candidates")
        precondition(groups.allSatisfy { (1...5).contains($0.count) }, "Each row contains 1 to 5 candidates")
        precondition(model.visibleCandidates.count == 5, "Long first candidate and four short candidates all fit")
        model.selected = 4; model.revealSelectedCandidate()
        precondition(model.visibleCandidates.contains(4), "Keyboard selection stays visible")
        model.selected = 0; model.candidateStart = 0
        for candidates in [["你好", "您好", "逆号", "拟好", "你"], ["我在输入很多", "我在", "我再", "窝在", "卧在"], ["这是一个很长的候选句子用于完整查看", "测试", "内容"]] {
            model.candidates = candidates
            model.candidateStart = 0
            let count = model.visibleCandidates.count
            let occupied = model.visibleCandidates.reduce(CGFloat.zero) { $0 + model.visibleCandidateWidth($1) }
            precondition(abs(occupied + CGFloat(count-1) * 4 - CandidateModel.rowWidth) < 0.01, "Text widths plus evenly shared remainder fill the row")
        }
        model.clipboardMode = true
        model.language = .en; model.enabledLanguages = [.id]
        model.original = "A short selection."
        let compact = model.displayHeight
        precondition(compact < 240, "Short selection avoids empty fixed-height space")
        model.original = String(repeating: "A longer selection requiring scrolling. ", count: 100)
        precondition(model.displayHeight > compact && model.displayHeight <= 420, "Long selection grows within a height limit")
        model.enabledLanguages = Language.targets
        precondition(model.displayHeight == 420, "Many selected languages scroll inside the capped panel")
        model.selectingLanguages = true
        precondition(model.displayHeight == 340, "Language picker remains bounded")
        model.selectingLanguages = false; model.clipboardMode = false
        model.original = "测试"
        model.candidates = ["你好", "您好", "拟好", "你"]
        model.language = .zh; model.translationSource = .zh; model.enabledLanguages = [.zh, .en, .id]
        let twoTargets = model.displayHeight
        precondition(twoTargets >= 270 && twoTargets < 420,
                     "Two default translation rows include their card padding before candidates")
        model.enabledLanguages = [.zh, .en]
        let oneExpanded = model.displayHeight
        model.enabledLanguages = [.zh, .en, .id]
        precondition(twoTargets - oneExpanded == CandidateModel.translationHeaderHeight + 54 + 10 + 2 * CandidateModel.translationBlockSpacing,
                     "Every expanded row includes header-to-card and group spacing")
        model.enabledLanguages = [.zh, .en, .id, .ja]
        precondition(model.displayHeight > twoTargets && model.displayHeight < 420,
                     "Three default translation rows fit fully before candidates")
        model.enabledLanguages = [.zh, .en, .id]
        model.sentenceMode = true
        precondition(model.displayedLanguages == [.id, .en] && model.displayHeight == twoTargets,
                     "Sentence mode does not add a translation row for its source language")
        for source in [Language.zh, .en, .id] {
            model.language = source
            model.translationSource = source
            precondition(!model.displayedLanguages.contains(source), "Sentence mode never duplicates the source language")
        }
        model.language = .zh
        model.translationSource = .zh
        model.original = "work"
        model.translationSource = .en
        precondition(model.displayedLanguages == [.id, .zh] && model.language == .zh,
                     "English candidate in Chinese input shows Chinese translation without changing input mode")
        model.original = "测试"
        model.translationSource = .zh
        model.sentenceMode = false
        model.enabledLanguages = [.zh, .en]
        let oneTarget = model.displayHeight
        precondition(oneTarget < twoTargets && oneTarget > 150, "Disabling a target removes its row and shrinks input panel")
        model.toggleCollapsedLanguage(.en)
        let folded = model.displayHeight
        precondition(folded < oneTarget && model.requestedLanguages == [.zh], "Folding keeps only its header and removes the request target")
        model.enabledLanguages = [.zh]
        precondition(model.displayedLanguages.isEmpty && model.collapsedLanguages.contains(.en) && model.displayHeight <= 130,
                     "All targets off leaves a compact candidate-only panel")
        model.enabledLanguages = [.zh, .en, .id]
        precondition(model.collapsedLanguages.contains(.en), "Re-enabling a target keeps its fold state")
        let restored = CandidateModel(defaults: defaults)
        precondition(restored.collapsedLanguages.contains(.en), "Input fold state survives a new model")
        restored.clipboardMode = true
        restored.restoreCollapsedLanguages()
        precondition(restored.collapsedLanguages.isEmpty, "Selection fold state is independent of input fold state")
        restored.toggleCollapsedLanguage(.id)
        let selectionRestored = CandidateModel(defaults: defaults)
        selectionRestored.clipboardMode = true
        selectionRestored.restoreCollapsedLanguages()
        precondition(selectionRestored.collapsedLanguages == [.id], "Selection fold state survives a new popup")
        let lessonSession = TranslationSession(translator: LayoutTranslator(), cache: TranslationCache())
        let lessonModel = CandidateModel(translation: lessonSession, defaults: defaults)
        lessonModel.original = "专用于学习面板的测试"
        lessonModel.translationSource = .zh
        lessonModel.enabledLanguages = [.zh, .en, .id]
        lessonModel.collapsedLanguages = []
        var learnedLanguages: [Language] = []
        lessonModel.learn = { learnedLanguages.append($0) }
        var lessonSettings = TranslationSettings()
        lessonSettings.source = .zh
        lessonSettings.enabledLanguages = [.en, .id]
        lessonSession.update(text: lessonModel.original, composing: false, settings: lessonSettings,
                             apiKey: "fixture-only", immediate: true)
        await lessonSession.waitForCurrentRequest()
        lessonModel.toggleLesson()
        precondition(learnedLanguages.isEmpty, "Two expanded learning languages require an explicit choice")
        lessonModel.toggleLesson()
        lessonModel.toggleCollapsedLanguage(.id)
        lessonModel.toggleLesson()
        precondition(learnedLanguages == [.en], "One expanded learning language starts automatically once")
        lessonModel.tryAutomaticLesson()
        precondition(learnedLanguages == [.en], "Automatic learning does not duplicate a request")
        model.toggleCollapsedLanguage(.en)
        let panel = CandidatePanel(model: model)
        let physical = NSScreen.main!.frame
        let visual = CandidateModel(defaults: defaults)
        visual.language = .zh
        visual.translationSource = .zh
        visual.original = "测试"
        visual.candidates = ["测试", "文字", "输入", "候选", "内容"]
        let visualPanel = CandidatePanel(model: visual)
        let previewCaret = CGRect(x: physical.minX + 160, y: physical.minY + 90, width: 2, height: 20)
        for (targets, name) in [([Language.en], "one"), ([.en, .id], "two"),
                                ([.en, .id, .ja], "three"), ([], "none")] {
            visual.enabledLanguages = targets
            visualPanel.present(near: previewCaret)
            try await Task.sleep(for: .milliseconds(150))
            print("PANEL_VISUAL", name, visualPanel.isVisible, visualPanel.windowNumber, visualPanel.frame, visual.displayHeight, visual.translationViewportHeight)
            fflush(stdout)
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(visualPanel.windowNumber), ".build/panel-\(name)-targets.png"]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0, "Panel visual capture succeeded")
        }
        visual.enabledLanguages = [.en, .id]
        visual.toggleCollapsedLanguage(.id)
        visualPanel.present(near: previewCaret)
        try await Task.sleep(for: .milliseconds(150))
        let foldedCapture = Process()
        foldedCapture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        foldedCapture.arguments = ["-x", "-l", String(visualPanel.windowNumber), ".build/panel-folded-target.png"]
        try foldedCapture.run()
        foldedCapture.waitUntilExit()
        precondition(foldedCapture.terminationStatus == 0, "Folded panel visual capture succeeded")
        visual.toggleCollapsedLanguage(.id)
        visual.expanded = true
        visual.lesson = nil
        visual.lessonStatus = ""
        for state in ["opened", "filled"] {
            if state == "filled" {
                let lesson = #"{"structure":"Hello：你好","points":["用于日常问候"],"register":"日常","example":"Hello, Lin! 你好，林！","ipa":"/həˈloʊ/","pronunciation":"重音在第二音节。","vocabulary":[{"word":"Hello","ipa":"/həˈloʊ/","meaning":"你好"}]}"#
                visual.lesson = try JSONDecoder().decode(GrammarLesson.self, from: Data(lesson.utf8))
            }
            visualPanel.present(near: previewCaret)
            try await Task.sleep(for: .milliseconds(180))
            precondition(!(visualPanel.contentView is NSScrollView),
                         "Lesson overflow cannot scroll the entire panel or hide its header")
            let capture = Process()
            capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            capture.arguments = ["-x", "-l", String(visualPanel.windowNumber), ".build/panel-lesson-\(state).png"]
            try capture.run()
            capture.waitUntilExit()
            precondition(capture.terminationStatus == 0, "Lesson \(state) visual capture succeeded")
            if state == "filled" {
                let screenTop = NSScreen.screens.first?.frame.maxY ?? 0
                let pointer = CGPoint(x: visualPanel.frame.midX, y: screenTop - visualPanel.frame.midY)
                if let scroll = CGEvent(scrollWheelEvent2Source: nil, units: .line,
                                        wheelCount: 1, wheel1: -7, wheel2: 0, wheel3: 0) {
                    scroll.location = pointer
                    scroll.post(tap: .cghidEventTap)
                    try await Task.sleep(for: .milliseconds(180))
                    let after = Process()
                    after.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
                    after.arguments = ["-x", "-l", String(visualPanel.windowNumber), ".build/panel-lesson-scrolled.png"]
                    try after.run()
                    after.waitUntilExit()
                    precondition(after.terminationStatus == 0, "Scrolled lesson visual capture succeeded")
                }
            }
        }
        visual.expanded = false
        visual.lesson = nil
        visual.enabledLanguages = [.en, .id]
        visualPanel.present(near: previewCaret)
        let lessonWindow = visualPanel.windowNumber
        let compactHeight = visualPanel.frame.height
        visual.toggleLesson()
        visualPanel.present(near: previewCaret)
        var lessonFrames: [CGFloat] = []
        for _ in 0..<30 {
            lessonFrames.append(visualPanel.frame.height)
            try await Task.sleep(for: .milliseconds(16))
        }
        print("LESSON_RESIZE from=\(compactHeight) frames=\(lessonFrames.map { Int($0) })")
        precondition(visualPanel.isVisible && visualPanel.windowNumber == lessonWindow,
                     "Learning expansion keeps the same visible panel window")
        visual.toggleLesson()
        visualPanel.present(near: previewCaret)
        precondition(visualPanel.isVisible && visualPanel.windowNumber == lessonWindow,
                     "Closing learning keeps the same visible panel window")
        visualPanel.orderOut(nil)
        panel.present(near: CGRect(x: physical.minX + 21, y: physical.minY + 49, width: 0, height: 19))
        precondition(panel.isVisible && physical.contains(panel.frame), "Fullscreen bottom caret cannot be rejected by hidden Dock reservation")
        panel.orderOut(nil)
        let visible = NSScreen.main!.visibleFrame
        for fraction in [0.2, 0.5, 0.85] {
            panel.orderOut(nil)
            let caret = CGRect(x: visible.minX + 120, y: visible.minY + visible.height * fraction, width: 2, height: 20)
            model.original = "专用于布局测试的文字"
            model.candidates = ["测试", "候选", "内容", "输入", "选择"]
            precondition(model.visibleCandidates.count == 5, "Five short candidates fit on one row")
            model.expanded = false
            session.invalidate()
            try await Task.sleep(for: .milliseconds(50))
            panel.present(near: caret)
            let original = panel.frame
            var previous = original
            var settings = TranslationSettings()
            settings.source = .zh
            settings.translationCacheDays = 0
            session.update(text: model.original, composing: false, settings: settings, apiKey: "fixture-only", immediate: true)
            for step in 0..<12 {
                if step == 5 { model.candidates = Array(repeating: "这是一个用于验证长候选框布局的句子", count: 5); precondition(model.visibleCandidates.count == 1, "One long candidate occupies the row") }
                if step == 8 { model.expanded = true }
                try await Task.sleep(for: .milliseconds(80))
                panel.present(near: caret)
                let current = panel.frame
                precondition(abs(current.width - CandidateModel.panelWidth) < 1 && current.height <= 540,
                             "Panel fits active content within available screen space")
                if step < 8 { precondition(abs(current.height - original.height) < 1, "Candidate length does not resize the panel") }
                else { precondition(current.height > original.height, "Opening the learning area grows the panel") }
                precondition(abs(current.minX - original.minX) < 1)
                let above = current.minY >= caret.maxY
                _ = previous.minY >= caret.maxY
                precondition(above || current.maxY <= caret.minY || current.intersects(caret) == false,
                             "Panel remains on one side of the caret while content changes")
                previous = current
                precondition(!current.intersects(caret))
                precondition(visible.contains(current))
                if let scroll = panel.contentView as? NSScrollView, let document = scroll.documentView,
                   document.bounds.height > scroll.contentView.bounds.height + 1 {
                    let shown = scroll.contentView.documentVisibleRect
                   precondition(shown.height > 0, "Constrained panel retains a visible content region")
                }
            }
            print("PASS · Stream growth, long candidates, lesson expansion at screen fraction \(fraction)")
        }
        panel.orderOut(nil)
        session.invalidate()
    }
}
