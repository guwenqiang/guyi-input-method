import Foundation
import Combine

@MainActor
public final class TranslationSession: ObservableObject {
    @Published public private(set) var result: Translation?
    @Published public private(set) var status = "输入原文，稍作停顿即可翻译"
    @Published public private(set) var busy = false
    @Published public private(set) var preview: [String: String] = [:]
    @Published public private(set) var readyLanguages: Set<Language> = []
    public private(set) var currentText = ""
    private var generation = 0
    private var task: Task<Void, Never>?
    private let translator: Translating
    private let cache: TranslationCache
    private var activeKey: Data?
    private var activeCredential = ""
    private var activeSettings: TranslationSettings?
    private var activeCacheRevision = -1
    private var networkStarted = false

    public init(translator: Translating = OpenAITranslator(), cache: TranslationCache? = nil) {
        self.translator = translator
        self.cache = cache ?? .shared
    }

    public func invalidate(message: String = "输入原文，稍作停顿即可翻译") {
        currentText = ""
        generation += 1
        task?.cancel()
        task = nil
        result = nil
        preview = [:]
        readyLanguages = []
        activeKey = nil
        busy = false
        networkStarted = false
        status = message
    }

    public func clearCache() { cache.clear() }
    public func waitForCurrentRequest() async { await task?.value }

    public func update(text: String, composing: Bool, settings: TranslationSettings, apiKey: String, immediate: Bool = false) {
        if SensitiveContentPolicy.resemblesSecret(text) {
            currentText = ""
            invalidate(message: "敏感内容不翻译、不缓存")
            return
        }
        if SelectionTranslationPolicy.isAddressOnly(text) {
            invalidate(message: ShortcutMessages.text(.addressOnly))
            return
        }
        cache.configure(days: settings.effectiveCacheDays)
        let cacheKey = TranslationCache.key(text: text, settings: settings)
        if !composing, activeKey == cacheKey, activeCredential == apiKey,
           activeSettings == settings, activeCacheRevision == cache.revision, busy || result != nil,
           !immediate || networkStarted || result != nil { return }
        invalidate()
        currentText = text
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        guard !composing else { status = "正在组词…"; return }
        guard !settings.translationTargets.isEmpty else { status = "译文已折叠 · 仅本地输入"; return }
        guard text.count <= 4_000 else { status = TranslationError.tooLong.localizedDescription; return }
        guard settings.automatic || immediate else { status = "自动翻译已关闭"; return }
        activeKey = cacheKey
        activeCredential = apiKey
        activeSettings = settings
        activeCacheRevision = cache.revision
        if let local = LocalPhrases.lookup(text, settings: settings) {
            result = local
            status = "本地常用短语 · 无需联网"
            return
        }
        if let cached = cache.get(cacheKey) { result = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text); status = "译文缓存 · 无需联网"; return }
        let revision = generation
        let cacheRevision = cache.revision
        busy = true
        status = immediate ? "正在翻译…" : "等待输入停顿…"
        task = Task { [weak self] in
            do {
                if let cached = await self?.cache.getPersisted(cacheKey) {
                    guard let self, revision == self.generation, !Task.isCancelled else { return }
                    self.result = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text)
                    self.busy = false
                    self.status = "本地译文缓存 · 无需联网"
                    return
                }
                try Task.checkCancellation()
                guard !apiKey.isEmpty else { throw TranslationError.missingKey }
                if !immediate { try await Task.sleep(nanoseconds: UInt64(max(0, min(1500, settings.debounceMilliseconds))) * 1_000_000) }
                guard let self, revision == self.generation else { return }
                self.status = "正在翻译…"
                self.networkStarted = true
                let start = Date()
                // URLSession's request timeout resets while bytes trickle in.
                // Bound visible waiting independently of the transport timeout.
                let firstLimit = min(8.0, max(0.05, settings.timeoutSeconds))
                let totalLimit = min(20.0, max(firstLimit, settings.timeoutSeconds))
                let watchdog = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(firstLimit * 1_000_000_000))
                        guard let self, revision == self.generation, self.busy else { return }
                        if self.preview.isEmpty { self.invalidate(message: TranslationError.timeout.localizedDescription); return }
                        try await Task.sleep(nanoseconds: UInt64((totalLimit - firstLimit) * 1_000_000_000))
                        if revision == self.generation, self.busy { self.invalidate(message: TranslationError.timeout.localizedDescription) }
                    } catch {}
                }
                defer { watchdog.cancel() }
                let translated: Translation
                if let streaming = self.translator as? StreamingTranslating {
                    translated = try await streaming.stream(text, settings: settings, apiKey: apiKey) { [weak self] fields in
                        await self?.receive(fields, revision: revision, start: start)
                    }
                } else {
                    translated = try await self.translator.translate(text, settings: settings, apiKey: apiKey)
                }
                try Task.checkCancellation()
                guard revision == self.generation else { return }
                self.cache.put(translated, key: cacheKey, languages: settings.translationTargets, expectedRevision: cacheRevision, includeSource: settings.translateWholeSelection == true)
                self.result = translated
                self.status = String(format: "完成 · %.2f 秒 · %@", Date().timeIntervalSince(start), settings.model)
                self.busy = false
                self.preview = [:]
            } catch {
                guard let self, revision == self.generation, !Task.isCancelled else { return }
                self.busy = false
                self.preview = [:]
                self.readyLanguages = []
                self.status = error.localizedDescription
            }
        }
    }

    private func receive(_ fields: [String: String], revision: Int, start: Date) {
        guard revision == generation else { return }
        var changed = false
        for language in activeSettings?.translationTargets ?? [] {
            if let value = fields[language.rawValue], preview[language.rawValue] != value {
                preview[language.rawValue] = value
                changed = true
            }
            if fields["_ready_" + language.rawValue] == "1", !readyLanguages.contains(language) {
                readyLanguages.insert(language)
                changed = true
            }
        }
        guard changed else { return }
        status = String(format: "已收到译文 · %.2f 秒 · 正在完成校验", Date().timeIntervalSince(start))
    }

    public func selectableText(for language: Language) -> String? {
        if let result { return result.text(for: language) }
        return readyLanguages.contains(language) ? preview[language.rawValue] : nil
    }
}
