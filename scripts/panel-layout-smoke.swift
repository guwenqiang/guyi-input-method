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
        let model = CandidateModel(translation: session)
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
        model.language = .zh; model.enabledLanguages = [.zh, .en, .id]
        precondition(model.displayHeight == CandidateModel.panelHeight, "Typing keeps its stable size")
        let panel = CandidatePanel(model: model)
        let physical = NSScreen.main!.frame
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
                precondition(abs(current.width - CandidateModel.panelWidth) < 1 && abs(current.height - CandidateModel.panelHeight) < 1,
                             "Panel size remains fixed across candidate and lesson changes when one side fits")
                precondition(abs(current.minX - original.minX) < 1)
                let above = current.minY >= caret.maxY
                let wasAbove = previous.minY >= caret.maxY
                if above == wasAbove {
                    precondition(abs((above ? current.minY : current.maxY) - (above ? previous.minY : previous.maxY)) < 1)
                }
                previous = current
                precondition(!current.intersects(caret))
                precondition(visible.contains(current))
                if let scroll = panel.contentView as? NSScrollView, let document = scroll.documentView,
                   document.bounds.height > scroll.contentView.bounds.height + 1 {
                    let shown = scroll.contentView.documentVisibleRect
                    precondition(abs(shown.maxY - document.bounds.maxY) < 2, "Constrained panel must retain the source/candidate region")
                }
            }
            print("PASS · Stream growth, long candidates, lesson expansion at screen fraction \(fraction)")
        }
        panel.orderOut(nil)
        session.invalidate()
    }
}
