import SwiftUI
import GuyiCore

@MainActor
final class CandidateModel: ObservableObject {
    @Published var preedit = ""
    @Published var themeSettings = TranslationSettings()
    @Published var original = ""
    @Published var candidates: [String] = [] {
        didSet { if oldValue != candidates { cachedWidths = nil; cachedGroups = nil } }
    }
    private var cachedWidths: [CGFloat]?
    private var cachedGroups: [Range<Int>]?
    private var cachedTextHeights: [String: CGFloat] = [:]
    @Published var selected = 0
    @Published var language = Language.zh
    @Published var enabledLanguages: [Language] = [.zh, .en, .id]
    @Published var selectedOutput = Language.zh
    @Published var clipboardMode = false
    @Published var showPinyin = false
    @Published var sentenceMode = false
    @Published var awaitingConfirmation = false
    @Published var quickContentStatus = ""
    @Published var calculationExpression = ""
    @Published var calculationResult: String?
    @Published var calculationError = ""
    var confirmCalculation: (() -> Void)?
    @Published var page = 0
    @Published var lastPage = true
    static let panelWidth: CGFloat = 460
    static let panelHeight: CGFloat = 300
    static let rowWidth: CGFloat = panelWidth - 20
    @Published var selectingLanguages = false
    private func textHeight(_ text: String, font: CGFloat, width: CGFloat) -> CGFloat {
        let key = "\(font):\(width):" + text
        if let value = cachedTextHeights[key] { return value }
        let height = ceil((text as NSString).boundingRect(with: NSSize(width: width, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: NSFont.systemFont(ofSize: font)]).height)
        if cachedTextHeights.count >= 64 { cachedTextHeights.removeAll(keepingCapacity: true) }
        cachedTextHeights[key] = height
        return height
    }
    var originalHeight: CGFloat { clipboardMode ? min(80, max(30, textHeight(original, font: 16, width: 380) + 8)) : 55 }
    func translationHeight(_ language: Language) -> CGFloat {
        guard clipboardMode else { return 54 }
        let text = translation.result?.text(for: language) ?? original
        return min(110, max(30, textHeight(text, font: 14, width: 330) + 8))
    }
    var displayHeight: CGFloat {
        if !calculationExpression.isEmpty {
            let contentHeight = textHeight(calculationExpression, font: 14, width: Self.rowWidth) +
                textHeight(calculationResult ?? calculationError, font: 22, width: Self.rowWidth)
            return min(260, max(165, contentHeight + 112))
        }
        guard clipboardMode else { return Self.panelHeight }
        if selectingLanguages { return 340 }
        let targets = enabledLanguages
        let rows = targets.reduce(CGFloat.zero) { $0 + translationHeight($1) + 30 }
        return min(420, max(150, 60 + originalHeight + rows + (expanded ? 210 : 0)))
    }
    @Published var candidateStart = 0
    var candidateGroups: [Range<Int>] {
        if let cachedGroups { return cachedGroups }
        var groups: [Range<Int>] = []
        var start = 0
        while start < candidates.count {
            var end = start, width: CGFloat = 0
            while end < candidates.count, end - start < 5 {
                let next = candidateWidth(end) + (end == start ? 0 : 4)
                if end > start, width + next > Self.rowWidth { break }
                width += next
                end += 1
            }
            groups.append(start..<end)
            start = end
        }
        cachedGroups = groups
        return groups
    }
    func candidateWidth(_ index: Int) -> CGFloat {
        guard candidates.indices.contains(index) else { return 0 }
        if cachedWidths == nil {
            let font = NSFont.systemFont(ofSize: 16, weight: .semibold)
            cachedWidths = candidates.map { min(Self.rowWidth, ceil(($0 as NSString).size(withAttributes: [.font: font]).width) + 28) }
        }
        return cachedWidths?[index] ?? 0
    }
    var visibleCandidates: Range<Int> {
        candidateGroups.first(where: { $0.contains(candidateStart) }) ?? 0..<0
    }
    func visibleCandidateWidth(_ index: Int) -> CGFloat {
        let count = max(1, visibleCandidates.count)
        let used = visibleCandidates.reduce(CGFloat.zero) { $0 + candidateWidth($1) }
        let extra = max(0, Self.rowWidth - used - CGFloat(count - 1) * 4) / CGFloat(count)
        return candidateWidth(index) + extra
    }
    var hasPreviousCandidates: Bool { candidateStart > 0 || page > 0 }
    var hasNextCandidates: Bool { visibleCandidates.upperBound < candidates.count || !lastPage }
    func revealSelectedCandidate() {
        candidateStart = candidateGroups.first(where: { $0.contains(selected) })?.lowerBound ?? 0
    }
    @Published var lesson: GrammarLesson?
    @Published var lessonStatus = ""
    @Published var lessonLanguage = Language.en
    @Published var expanded = false
    let translation: TranslationSession
    init(translation: TranslationSession? = nil) { self.translation = translation ?? TranslationSession() }
    var pick: ((Int) -> Void)?
    var insert: ((Language) -> Void)?
    var copyText: ((String) -> Void)?
    @Published var copiedText = ""
    var learn: ((Language) -> Void)?
    var retryTranslation: (() -> Void)?
    var settings: (() -> Void)?
    var cycle: (() -> Void)?
    var turnPage: ((Bool) -> Void)?
    var toggleLanguage: ((Language) -> Void)?
    var toggleSentence: (() -> Void)?
    var emoji: (() -> Void)?
}

struct CandidateView: View {
    @ObservedObject var model: CandidateModel
    @ObservedObject var translation: TranslationSession
    @ObservedObject private var interfaceLanguage = InterfaceLanguage.shared
    @ObservedObject private var speech = TranslationSpeech.shared
    private var theme: CandidateTheme { CandidateTheme(settings: model.themeSettings) }
    private var accent: Color { theme.accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if !model.calculationExpression.isEmpty {
                Text(Localizer.text("精确计算")).font(.caption).foregroundStyle(.secondary)
                Text(model.calculationExpression).font(.system(size: 14, design: .monospaced))
                    .fixedSize(horizontal: false, vertical: true)
                if let result = model.calculationResult {
                    Button(action: { model.confirmCalculation?() }) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(result).font(.system(size: 22, weight: .semibold, design: .monospaced))
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 4)
                            Text("↩").foregroundStyle(.secondary)
                        }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                            .background(accent.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                    }.buttonStyle(.plain)
                    Text(Localizer.text("回车插入结果 · Esc 关闭")).font(.caption2).foregroundStyle(.secondary)
                } else {
                    Text(model.calculationError).foregroundStyle(.orange)
                    Text(Localizer.text("Esc 关闭后修改公式")).font(.caption2).foregroundStyle(.secondary)
                }
            } else {
            HStack(spacing: 8) {
                Text(model.quickContentStatus.isEmpty ? (model.clipboardMode ? Localizer.text("选文翻译") : Brand.name) : model.quickContentStatus)
                    .font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(model.quickContentStatus.isEmpty ? Color.secondary : Color.primary).lineLimit(1)
                    .help(model.quickContentStatus)
                Spacer()
                if model.clipboardMode {
                    Button(Localizer.text("翻译语言")) { model.selectingLanguages.toggle() }
                        .buttonStyle(.plain).font(.caption)
                } else {
                    Button(action: { model.emoji?() }) { Image(systemName: "face.smiling") }
                        .buttonStyle(.plain).help(Localizer.text("表情与符号"))
                }
                if !model.clipboardMode {
                Button(action: { model.toggleSentence?() }) {
                    Image(systemName: model.sentenceMode ? "text.badge.checkmark" : "text.alignleft")
                        .foregroundStyle(model.sentenceMode ? accent : Color.secondary)
                }.buttonStyle(.plain)
                    .help(Localizer.text(model.sentenceMode ? "整句模式已开启 · 点击关闭" : "短句模式 · 点击开启整句"))
                    .accessibilityLabel(Localizer.text("切换整句模式"))
                }
                if translation.busy {
                    ProgressView().controlSize(.mini).help("正在翻译")
                } else if translation.result == nil && translation.preview.isEmpty && !model.original.isEmpty {
                    Button(action: { model.retryTranslation?() }) { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.plain).foregroundStyle(.secondary)
                        .help(Localizer.text("重新翻译")).accessibilityLabel(Localizer.text("重新翻译"))
                        .disabled(model.retryTranslation == nil)
                } else if let note = translation.result?.note, !note.isEmpty {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                        .help(note).accessibilityLabel(Localizer.text("翻译说明"))
                }
                Button(action: { model.expanded.toggle() }) { Image(systemName: "book.closed") }
                    .buttonStyle(.plain).help("音标与学习").accessibilityLabel(Localizer.text("读懂 · 学会用"))
                if model.clipboardMode {
                    Text(model.language.title).font(.caption).foregroundStyle(.secondary)
                } else {
                Button(action: { model.cycle?() }) {
                    Text(Localizer.text(model.language.title)).font(.caption.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(accent.opacity(0.12), in: Capsule())
                }.buttonStyle(.plain).help(Localizer.text("切换原文语言") + " " + InputShortcuts.display("cycleLanguage", settings: model.themeSettings))
                }
                Button(action: { model.settings?() }) { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.plain).help("设置")
            }
            ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 7) {
            if model.clipboardMode, model.selectingLanguages {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                    ForEach(Language.targets) { language in
                        Toggle(language.title, isOn: Binding(get: { model.enabledLanguages.contains(language) }, set: { _ in model.toggleLanguage?(language) }))
                            .toggleStyle(.checkbox).font(.caption)
                    }
                }.padding(.vertical, 5)
                Button(Localizer.text("完成")) { model.selectingLanguages = false }.buttonStyle(.bordered)
            } else {
            if model.expanded {
                Divider()
                HStack {
                    Text("读懂 · 学会用").font(.caption.weight(.semibold))
                    Spacer()
                    Button("English") { model.learn?(.en) }.disabled(translation.result?.en.isEmpty != false)
                    Button("Indonesia") { model.learn?(.id) }.disabled(translation.result?.id.isEmpty != false)
                }.font(.caption)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if let lesson = model.lesson {
                            if let ipa = lesson.ipa, !ipa.isEmpty {
                                Text(Localizer.text(model.lessonLanguage == .en ? "美式音标 · AI 辅助" : "印尼语音标 · AI 辅助"))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text(ipa).font(.system(size: 17)).textSelection(.enabled)
                            }
                            if let pronunciation = lesson.pronunciation, !pronunciation.isEmpty {
                                Text(pronunciation).font(.callout)
                            }
                            ForEach(Array((lesson.vocabulary ?? []).enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.word + "  " + item.ipa).font(.callout.weight(.medium))
                                    Text(item.meaning).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text(lesson.structure).font(.callout)
                            ForEach(Array(lesson.points.enumerated()), id: \.offset) { _, point in
                                Text("• " + point).font(.callout)
                            }
                            Text(lesson.register).font(.caption).foregroundStyle(.secondary)
                            Text(lesson.example).font(.callout).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        } else {
                            Text(Localizer.text(model.lessonStatus.isEmpty ? "选择语言，查看音标、词义和句式。" : model.lessonStatus))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.defaultScrollAnchor(.top).id(model.lessonLanguage).frame(height: 180)
            }
            ForEach(Language.targets.reversed().filter { (model.clipboardMode || model.sentenceMode || $0 != model.language) && (model.enabledLanguages.contains($0) || (!model.clipboardMode && [Language.zh, .en, .id].contains($0))) }) { language in
                VStack(alignment: .leading, spacing: 2) {
                    Button(action: { model.toggleLanguage?(language) }) {
                        HStack {
                            Image(systemName: model.enabledLanguages.contains(language) ? "chevron.down" : "chevron.right")
                            Text(Localizer.text(language.title))
                            if !model.enabledLanguages.contains(language) { Text("已关闭").foregroundStyle(.secondary) }
                            Spacer()
                        }.font(.system(size: 10))
                    }.buttonStyle(.plain)
                    if model.enabledLanguages.contains(language) { row(language) }
                }
            }
            }
            }
            }.defaultScrollAnchor(.top).id(model.original + (model.expanded ? "|lesson" : "|translation") + (model.selectingLanguages ? "|languages" : ""))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            if model.showPinyin {
                Text(model.preedit.isEmpty ? " " : model.preedit).font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary).lineLimit(1).frame(height: 16)
            }
            if !model.candidates.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(model.visibleCandidates), id: \.self) { index in
                        candidateButton(index, model.candidates[index])
                    }
                }.frame(height: 32)
                HStack {
                    Button(action: { model.turnPage?(false) }) {
                        Image(systemName: "chevron.up").frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).help("上面的候选").disabled(!model.hasPreviousCandidates).opacity(model.hasPreviousCandidates ? 1 : 0.25)
                    Button(action: { model.turnPage?(true) }) {
                        Image(systemName: "chevron.down").frame(maxWidth: .infinity)
                    }.buttonStyle(.plain).help("下面还有候选").disabled(!model.hasNextCandidates).opacity(model.hasNextCandidates ? 1 : 0.25)
                }.frame(height: 16)
            } else {
                HStack {
                    Text(model.awaitingConfirmation ? ShortcutMessages.text(.unconfirmed) : Localizer.text("原文"))
                        .font(.caption).foregroundStyle(.secondary)
                    ScrollView(.vertical) {
                        Text(model.original).font(.system(size: 16)).frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true).frame(minHeight: model.originalHeight, alignment: .leading)
                    }.defaultScrollAnchor(.top).id(model.original).frame(height: model.originalHeight)
                    Spacer(minLength: 0)
                    if model.clipboardMode {
                        let originalLanguage: Language = model.language == .auto
                            ? (model.original.unicodeScalars.contains(where: { $0.isASCII && CharacterSet.letters.contains($0) }) ? .en : .zh)
                            : model.language
                        let speaking = speech.language == originalLanguage && speech.spokenText == model.original
                        Button(action: { speech.toggle(model.original, language: originalLanguage) }) {
                            Image(systemName: speaking ? "stop.fill" : "speaker.wave.2")
                        }.buttonStyle(.plain).disabled(model.original.isEmpty || speech.voice(for: originalLanguage) == nil)
                            .help(Localizer.text(speaking ? "停止朗读" : "朗读原文"))
                            .accessibilityLabel(Localizer.text(speaking ? "停止朗读" : "朗读原文"))
                    } else {
                        Text("↩").font(.caption).foregroundStyle(.tertiary)
                    }
                }.frame(height: model.originalHeight, alignment: .center)
            }
            }
        }
        .padding(10).frame(width: CandidateModel.panelWidth, height: model.displayHeight, alignment: .top)
        .background(theme.background, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.primary.opacity(0.08)))
        .tint(accent)
        .environment(\.locale, interfaceLanguage.locale)
        .environment(\.colorScheme, theme.dark ? .dark : .light)
        .onChange(of: model.original) { _, _ in speech.stop() }
        .onChange(of: model.clipboardMode) { _, _ in model.selectingLanguages = false }
    }

    private func candidateButton(_ index: Int, _ candidate: String) -> some View {
        Button(action: { model.pick?(index) }) {
            HStack(spacing: 4) {
                Text("\(index - model.visibleCandidates.lowerBound + 1)").font(.caption2).foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Text(candidate).font(.system(size: 16, weight: index == model.selected ? .semibold : .regular))
                        .lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }.scrollIndicators(.hidden)
            }.padding(.horizontal, 5).padding(.vertical, 6)
                .frame(width: model.visibleCandidateWidth(index), height: 32)
                .foregroundStyle(index == model.selected && model.selectedOutput == model.language ? theme.selectedText : Color.primary)
                .background(index == model.selected && model.selectedOutput == model.language ? accent : .clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).help(candidate)
    }

    private func row(_ language: Language) -> some View {
        let result = translation.result
        let speakable = translation.selectableText(for: language)
        let speaking = speech.language == language && speech.spokenText == speakable
        return HStack(alignment: .center, spacing: 8) {
            Text(language == .zh ? "中" : language.rawValue.uppercased())
                .font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                .frame(width: 27, height: 24).background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 6))
            ScrollView(.vertical) {
                Text(result?.text(for: language) ?? translation.preview[language.rawValue] ?? (translation.busy ? Localizer.text("翻译中…") : translation.status))
                    .font(.system(size: 14)).foregroundStyle(result == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: model.translationHeight(language), alignment: .leading)
            }.defaultScrollAnchor(.top).id(model.original + language.rawValue).frame(height: model.translationHeight(language))
            Button(action: { if let speakable { model.copyText?(speakable) } }) {
                Image(systemName: model.copiedText == speakable ? "checkmark" : "doc.on.doc")
                    .frame(width: 22, height: 26)
            }.buttonStyle(.plain).disabled(speakable == nil)
                .help(Localizer.text("复制译文"))
                .accessibilityLabel(Localizer.text("复制译文") + " " + language.title)
            Button(action: { if let speakable { speech.toggle(speakable, language: language) } }) {
                Image(systemName: speaking ? "stop.fill" : "speaker.wave.2")
                    .frame(width: 22, height: 26)
            }.buttonStyle(.plain)
                .disabled(speakable == nil || speech.voice(for: language) == nil)
                .help(Localizer.text(speaking ? "停止朗读" : "朗读译文"))
                .accessibilityLabel(Localizer.text(speaking ? "停止朗读" : "朗读译文") + " " + language.title)
            if model.insert != nil {
            Button(action: { model.insert?(language) }) {
                Text(InputShortcuts.display(InputShortcuts.translationAction(language), settings: model.themeSettings).isEmpty ? "↩" : InputShortcuts.display(InputShortcuts.translationAction(language), settings: model.themeSettings)).font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 7).padding(.vertical, 5)
            }.buttonStyle(.bordered).disabled(translation.selectableText(for: language) == nil).help("上屏 " + language.title)
            }
        }.padding(5).background(model.selectedOutput == language ? accent.opacity(0.35) : (theme.dark ? Color.white : Color.black).opacity(0.035), in: RoundedRectangle(cornerRadius: 7))
    }
}

final class CandidatePanel: NSPanel {
    private var hostedContent: NSHostingView<CandidateView>?
    private let model: CandidateModel
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    init(model: CandidateModel) {
        self.model = model
        super.init(contentRect: NSRect(x: 0, y: 0, width: 524, height: 390), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        let host = NSHostingView(rootView: CandidateView(model: model, translation: model.translation))
        hostedContent = host
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = host
        contentView = scroll
    }
    func present(near caret: NSRect, avoiding: NSRect? = nil) {
        guard caret.height > 0 else { orderOut(nil); return }
        let size = NSSize(width: CandidateModel.panelWidth, height: model.displayHeight)
        guard let screen = NSScreen.screens.first(where: { $0.frame.intersects(caret.insetBy(dx: -0.5, dy: 0)) }) else { orderOut(nil); return }
        // Full-screen editors can place a valid caret where visibleFrame still
        // reserves the hidden Dock. In that case use the physical screen.
        let visible = screen.visibleFrame.intersects(caret.insetBy(dx: -0.5, dy: 0)) ? screen.visibleFrame : screen.frame
        let sameLine = isVisible && abs(placementCaret.minY - caret.minY) < 3 && abs(placementCaret.minX - caret.minX) < 3
        guard let frame = CandidatePlacement.frame(caret: caret, desired: size, visible: visible,
                                                  preferredAbove: sameLine ? placedAbove : nil, avoiding: avoiding, keepSide: model.clipboardMode && sameLine) else {
            orderOut(nil)
            return
        }
        hostedContent?.setFrameSize(size)
        let layoutChanged = !isVisible || self.frame.size != frame.size || lastContentSize != size
        placementCaret = caret
        placedAbove = frame.minY >= caret.maxY
        if self.frame != frame { setFrame(frame, display: true, animate: false) }
        if layoutChanged, let scroll = contentView as? NSScrollView, let host = hostedContent {
            scroll.layoutSubtreeIfNeeded()
            let bottom = max(0, size.height - scroll.contentView.bounds.height)
            scroll.contentView.scroll(to: NSPoint(x: 0, y: host.isFlipped ? bottom : 0))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        lastContentSize = size
        if !isVisible { orderFrontRegardless() }
    }
    private var placementCaret = NSRect.zero
    private var placedAbove = true
    private var lastContentSize = NSSize.zero
}
