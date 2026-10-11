import Foundation
import Combine
import OSLog

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
    private var networkStartedAt: Date?
    private let latencyLogger = Logger(subsystem: "app.guyi.inputmethod.Guyi", category: "TranslationLatency")
    private func auditLatency(_ stage: String, elapsed: TimeInterval, targets: Int) {
        guard UserDefaults.standard.bool(forKey: "diagnoseTranslationLatency") else { return }
        latencyLogger.notice("stage=\(stage, privacy: .public) elapsedMs=\(Int(elapsed * 1_000)) targets=\(targets)")
    }
    private func recordCancellation() {
        guard let networkStartedAt else { return }
        auditLatency("request-cancelled", elapsed: Date().timeIntervalSince(networkStartedAt),
                     targets: activeSettings?.translationTargets.count ?? 0)
        self.networkStartedAt = nil
    }

    public init(translator: Translating = OpenAITranslator(), cache: TranslationCache? = nil) {
        self.translator = translator
        self.cache = cache ?? .shared
    }

    public func invalidate(message: String = "输入原文，稍作停顿即可翻译") {
        recordCancellation()
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

    public func update(text: String, composing: Bool, settings: TranslationSettings, apiKey: String,
                       immediate: Bool = false, forceRefresh: Bool = false) {
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
        let cacheKey = TranslationCache.key(text: text, settings: settings, credential: apiKey)
        let requestedReady = result.map { current in
            settings.translationTargets.allSatisfy { !current.text(for: $0).isEmpty }
        } ?? true
        if !forceRefresh, !composing, activeKey == cacheKey, activeCredential == apiKey,
           activeSettings == settings, activeCacheRevision == cache.revision, busy || result != nil,
           !immediate || networkStarted || result != nil, busy || requestedReady { return }
        var oldContext = activeSettings
        oldContext?.enabledLanguages = nil
        var newContext = settings
        newContext.enabledLanguages = nil
        let reusable = !forceRefresh && !composing && currentText == text && activeCredential == apiKey &&
            activeCacheRevision == cache.revision && oldContext == newContext && result != nil
        if reusable, let result,
           settings.translationTargets.allSatisfy({ !result.text(for: $0).isEmpty }) {
            recordCancellation()
            generation += 1
            task?.cancel()
            task = nil
            preview = [:]
            readyLanguages = []
            busy = false
            activeKey = cacheKey
            activeSettings = settings
            if settings.translationTargets.isEmpty { status = "译文已折叠 · 仅本地输入" }
            else { cache.put(result, key: cacheKey, languages: settings.translationTargets,
                             expectedRevision: cache.revision, includeSource: settings.translateWholeSelection == true) }
            return
        }
        var retained = reusable ? result : nil
        if !forceRefresh, !composing, retained == nil {
            retained = cache.reusable(text: text, settings: settings, credential: apiKey)
        }
        var requestSettings = settings
        if forceRefresh || retained != nil {
            if let retained {
                requestSettings.enabledLanguages = settings.translationTargets.filter { retained.text(for: $0).isEmpty }
            }
            recordCancellation()
            generation += 1
            task?.cancel()
            task = nil
            preview = [:]
            readyLanguages = []
            busy = false
            networkStarted = false
        } else { invalidate() }
        let requestKey = TranslationCache.key(text: text, settings: requestSettings, credential: apiKey)
        let networkSettings = requestSettings
        let networkTargets = networkSettings.translationTargets
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
        if let retained, settings.translationTargets.allSatisfy({ !retained.text(for: $0).isEmpty }) {
            auditLatency("memory-hit", elapsed: 0, targets: settings.translationTargets.count)
            result = settings.translateWholeSelection == true ? retained : retained.restoringOriginal(text)
            cache.put(retained, key: cacheKey, languages: settings.translationTargets,
                      expectedRevision: cache.revision, includeSource: settings.translateWholeSelection == true)
            status = "译文缓存 · 无需联网"
            return
        }
        if let retained { result = settings.translateWholeSelection == true ? retained : retained.restoringOriginal(text) }
        if let local = LocalPhrases.lookup(text, settings: networkSettings) {
            result = retained?.merging(local) ?? local
            status = "本地常用短语 · 无需联网"
            return
        }
        if !forceRefresh, let cached = cache.get(cacheKey) {
            auditLatency("memory-hit", elapsed: 0, targets: settings.translationTargets.count)
            result = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text)
            status = "译文缓存 · 无需联网"
            return
        }
        if !forceRefresh, retained != nil, let cached = cache.get(requestKey) {
            let translated = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text)
            let combined = retained?.merging(translated) ?? translated
            cache.put(combined, key: cacheKey, languages: settings.translationTargets,
                      expectedRevision: cache.revision, includeSource: settings.translateWholeSelection == true)
            result = combined
            status = "译文缓存 · 无需联网"
            return
        }
        let revision = generation
        let cacheRevision = cache.revision
        let lookupStarted = Date()
        busy = true
        status = immediate ? "正在翻译…" : "等待输入停顿…"
        task = Task { [weak self] in
            do {
                var retained = retained
                var requestSettings = networkSettings
                var requestKey = requestKey
                var networkTargets = networkTargets
                if !forceRefresh, let cached = await self?.cache.getPersisted(cacheKey) {
                    guard let self, revision == self.generation, !Task.isCancelled else { return }
                    self.auditLatency("disk-hit", elapsed: Date().timeIntervalSince(lookupStarted), targets: settings.translationTargets.count)
                    self.result = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text)
                    self.busy = false
                    self.status = "本地译文缓存 · 无需联网"
                    return
                }
                if !forceRefresh, retained != nil, let cached = await self?.cache.getPersisted(requestKey) {
                    guard let self, revision == self.generation, !Task.isCancelled else { return }
                    let translated = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text)
                    let combined = retained?.merging(translated) ?? translated
                    self.cache.put(combined, key: cacheKey, languages: settings.translationTargets,
                                   expectedRevision: cacheRevision, includeSource: settings.translateWholeSelection == true)
                    self.result = combined
                    self.busy = false
                    self.status = "本地译文缓存 · 无需联网"
                    return
                }
                if !forceRefresh, retained == nil,
                   let cached = await self?.cache.persistedReusable(text: text, settings: settings, credential: apiKey) {
                    guard let self, revision == self.generation, !Task.isCancelled else { return }
                    retained = cached
                    if settings.translationTargets.allSatisfy({ !cached.text(for: $0).isEmpty }) {
                        self.auditLatency("disk-hit", elapsed: Date().timeIntervalSince(lookupStarted), targets: settings.translationTargets.count)
                        self.result = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text)
                        self.busy = false
                        self.status = "本地译文缓存 · 无需联网"
                        return
                    }
                    self.result = settings.translateWholeSelection == true ? cached : cached.restoringOriginal(text)
                    requestSettings.enabledLanguages = settings.translationTargets.filter { cached.text(for: $0).isEmpty }
                    requestKey = TranslationCache.key(text: text, settings: requestSettings, credential: apiKey)
                    networkTargets = requestSettings.translationTargets
                }
                try Task.checkCancellation()
                guard !apiKey.isEmpty else { throw TranslationError.missingKey }
                self?.auditLatency("cache-miss", elapsed: Date().timeIntervalSince(lookupStarted), targets: networkTargets.count)
                if !immediate { try await Task.sleep(nanoseconds: UInt64(max(0, min(1500, settings.debounceMilliseconds))) * 1_000_000) }
                guard let self, revision == self.generation else { return }
                self.status = "正在翻译…"
                self.networkStarted = true
                let start = Date()
                self.networkStartedAt = start
                self.auditLatency("network-start", elapsed: Date().timeIntervalSince(lookupStarted), targets: networkTargets.count)
                // URLSession's request timeout resets while bytes trickle in.
                // Bound visible waiting independently of the transport timeout.
                let firstLimit = min(settings.translateWholeSelection == true ? 30.0 : 8.0,
                                     max(0.05, settings.timeoutSeconds))
                let totalLimit = min(settings.translateWholeSelection == true ? 45.0 : 20.0,
                                     max(firstLimit, settings.timeoutSeconds))
                let watchdog = Task { @MainActor [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: UInt64(firstLimit * 1_000_000_000))
                        guard let self, revision == self.generation, self.busy else { return }
                        if self.preview.isEmpty {
                            if totalLimit <= firstLimit {
                                self.stopPending(TranslationError.timeout.localizedDescription, preservingResult: self.result != nil)
                                return
                            }
                            self.status = Localizer.text("翻译仍在处理…")
                        }
                        try await Task.sleep(nanoseconds: UInt64((totalLimit - firstLimit) * 1_000_000_000))
                        if revision == self.generation, self.busy {
                            self.stopPending(TranslationError.timeout.localizedDescription, preservingResult: self.result != nil)
                        }
                    } catch {}
                }
                defer { watchdog.cancel() }
                let translated: Translation
                if let streaming = self.translator as? StreamingTranslating {
                    let streamedTargets = networkTargets
                    translated = try await streaming.stream(text, settings: requestSettings, apiKey: apiKey) { [weak self] fields in
                        await self?.receive(fields, targets: streamedTargets, revision: revision, start: start)
                    }
                } else {
                    translated = try await self.translator.translate(text, settings: requestSettings, apiKey: apiKey)
                }
                try Task.checkCancellation()
                guard revision == self.generation else { return }
                self.cache.put(translated, key: requestKey, languages: networkTargets,
                               expectedRevision: cacheRevision, includeSource: settings.translateWholeSelection == true)
                self.cache.putReusable(translated, text: text, settings: requestSettings, credential: apiKey,
                                       expectedRevision: cacheRevision)
                let combined = retained?.merging(translated) ?? translated
                if requestKey != cacheKey {
                    self.cache.put(combined, key: cacheKey, languages: settings.translationTargets,
                                   expectedRevision: cacheRevision, includeSource: settings.translateWholeSelection == true)
                }
                self.result = combined
                self.networkStartedAt = nil
                self.auditLatency("network-complete", elapsed: Date().timeIntervalSince(start), targets: networkTargets.count)
                self.status = String(format: "完成 · %.2f 秒 · %@", Date().timeIntervalSince(start), settings.model)
                self.busy = false
                self.preview = [:]
            } catch {
                guard let self, revision == self.generation, !Task.isCancelled else { return }
                self.networkStartedAt = nil
                self.auditLatency("request-failed", elapsed: Date().timeIntervalSince(lookupStarted), targets: networkTargets.count)
                self.busy = false
                self.preview = [:]
                self.readyLanguages = []
                self.status = error.localizedDescription
            }
        }
    }

    private func stopPending(_ message: String, preservingResult: Bool) {
        guard preservingResult else { invalidate(message: message); return }
        recordCancellation()
        generation += 1
        task?.cancel()
        task = nil
        busy = false
        preview = [:]
        readyLanguages = []
        status = message
    }

    private func receive(_ fields: [String: String], targets: [Language], revision: Int, start: Date) {
        guard revision == generation else { return }
        let firstPreview = preview.isEmpty
        var changed = false
        for language in targets {
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
        if firstPreview && !preview.isEmpty {
            auditLatency("first-preview", elapsed: Date().timeIntervalSince(start), targets: targets.count)
        }
        if !readyLanguages.isEmpty {
            let source = activeSettings?.source ?? .auto
            let complete = Dictionary(uniqueKeysWithValues: readyLanguages.compactMap { language in
                preview[language.rawValue].map { (language.rawValue, $0) }
            })
            let additional = complete.filter { !["zh", "en", "id"].contains($0.key) }
            let partial = Translation(source: source,
                                      zh: source == .zh ? currentText : complete["zh"] ?? "",
                                      en: source == .en ? currentText : complete["en"] ?? "",
                                      id: source == .id ? currentText : complete["id"] ?? "",
                                      note: "", additional: additional.isEmpty ? nil : additional)
            result = result?.merging(partial) ?? partial
        }
        status = String(format: "已收到译文 · %.2f 秒 · 正在完成校验", Date().timeIntervalSince(start))
    }

    public func selectableText(for language: Language) -> String? {
        if let text = result?.text(for: language), !text.isEmpty { return text }
        return readyLanguages.contains(language) ? preview[language.rawValue] : nil
    }
}
