import AppKit
import GuyiCore
@MainActor
final class Preferences: ObservableObject {
    @Published private(set) var settings: TranslationSettings
    @Published private(set) var apiKey: String
    @Published private(set) var configured: Bool
    @Published private(set) var keyStatus = ""
    @Published private(set) var selectionTranslationPaused: Bool
    private let defaults: UserDefaults
    var inputLanguage: Language = .zh {
        didSet {
            guard Language.inputModes.contains(inputLanguage) else { return }
            defaults.set(inputLanguage.rawValue, forKey: "inputLanguage")
            if inputLanguage != .en {
                lastNonEnglishInputLanguage = inputLanguage
                defaults.set(inputLanguage.rawValue, forKey: "lastNonEnglishInputLanguage")
            }
        }
    }
    private(set) var lastNonEnglishInputLanguage: Language = .zh
    private var lastSelectionPauseToggle = Date.distantPast
    init(defaults: UserDefaults = .standard, readCredential: @escaping () -> LocalCredential.ReadResult = { LocalCredential.readResult() }) {
        self.defaults = defaults
        selectionTranslationPaused = defaults.bool(forKey: "selectionTranslationPaused")
        if let data = defaults.data(forKey: "translationSettings"),
           let saved = try? JSONDecoder().decode(TranslationSettings.self, from: data) { settings = saved }
        else { settings = TranslationSettings() }
        let keyResult = readCredential()
        if case .available(let value) = keyResult { apiKey = value } else { apiKey = "" }
        configured = defaults.bool(forKey: "configured")
        if let data = defaults.data(forKey: "translationSettings"),
           let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any], previous["backend"] as? String == "local" {
            var migrated = settings
            migrated.automatic = false
            migrated.translateClipboard = false
            settings = migrated
            if let encoded = try? JSONEncoder().encode(migrated) { defaults.set(encoded, forKey: "translationSettings") }
        }
        let savedInput = Language(rawValue: defaults.string(forKey: "inputLanguage") ?? "")
        let systemNative = Language.nativeInputMode()
        let initialInput = savedInput.flatMap { Language.inputModes.contains($0) ? $0 : nil } ??
            (Language.inputModes.contains(settings.source) ? settings.source : systemNative)
        let savedNative = Language(rawValue: defaults.string(forKey: "lastNonEnglishInputLanguage") ?? "")
        lastNonEnglishInputLanguage = savedNative.flatMap { $0 != .en && Language.inputModes.contains($0) ? $0 : nil } ??
            (initialInput == .en ? systemNative : initialInput)
        inputLanguage = initialInput
        switch keyResult {
        case .locked: keyStatus = "本地密钥配置不可读取，现有文件未被修改。"
        case .failed: keyStatus = "本地密钥配置不可读取，现有文件未被修改。"
        case .missing:
            if configured { keyStatus = "请填写此服务的 API Key。" }
        default: break
        }
        if !defaults.bool(forKey: "realtimeInputMigration") {
            if settings.debounceMilliseconds == 600 { settings.debounceMilliseconds = 120 }
            if let encoded = try? JSONEncoder().encode(settings) { defaults.set(encoded, forKey: "translationSettings") }
            defaults.set(true, forKey: "realtimeInputMigration")
        }
    }
    func save(_ draft: TranslationSettings, key: String, serviceName: String? = nil,
              serviceID: String? = nil, newService: Bool = false,
              defaultInputLanguage: Language? = nil) async throws {
        var draft = draft
        if draft.model != settings.model, !settings.model.isEmpty {
            var previous = draft.cachePreviousModels ?? settings.cachePreviousModels ?? []
            previous.removeAll { $0 == settings.model || $0 == draft.model }
            previous.insert(settings.model, at: 0)
            draft.cachePreviousModels = Array(previous.prefix(4))
        }
        if (newService || draft.effectiveAPIProtocol != settings.effectiveAPIProtocol || draft.endpoint != settings.endpoint),
           key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TranslationError.missingKey
        }
        _ = try draft.validatedURL()
        let encoded = try JSONEncoder().encode(draft)
        let newKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if !newService { try await ServiceProfiles.shared.remember(settings: settings, key: apiKey) }
        try await ServiceProfiles.shared.remember(settings: draft, key: newKey.isEmpty ? apiKey : newKey, name: serviceName, id: serviceID)
        if !newKey.isEmpty && newKey != apiKey {
            try await Task.detached { try LocalCredential.save(newKey) }.value
        }
        defaults.set(encoded, forKey: "translationSettings")
        defaults.set(true, forKey: "configured")
        if let defaultInputLanguage { inputLanguage = defaultInputLanguage }
        settings = draft
        if !newKey.isEmpty { apiKey = newKey }
        if !apiKey.isEmpty { keyStatus = "" }
        configured = true
        TranslationCache.shared.configure(days: draft.effectiveCacheDays)
        HotwordStore.shared.configure(enabled: draft.hotwordsEnabled != false)
        NotificationCenter.default.post(name: .guyiSettingsChanged, object: nil)
    }
    func toggleSentenceMode() {
        var updated = settings
        updated.sentenceComposition = settings.sentenceComposition != true
        guard let encoded = try? JSONEncoder().encode(updated) else { return }
        defaults.set(encoded, forKey: "translationSettings")
        settings = updated
        NotificationCenter.default.post(name: .guyiSentenceModeChanged, object: nil)
    }
    func toggleSelectionTranslation() {
        guard Date().timeIntervalSince(lastSelectionPauseToggle) > 0.15 else { return }
        lastSelectionPauseToggle = Date()
        selectionTranslationPaused.toggle()
        defaults.set(selectionTranslationPaused, forKey: "selectionTranslationPaused")
        NotificationCenter.default.post(name: .guyiSelectionPauseChanged, object: nil)
    }
    func saveSelectionLanguages(_ languages: [Language]) {
        var updated = settings
        updated.selectionLanguages = Language.targets.filter { languages.contains($0) }
        guard let data = try? JSONEncoder().encode(updated) else { return }
        defaults.set(data, forKey: "translationSettings")
        settings = updated
        NotificationCenter.default.post(name: .guyiSelectionLanguagesChanged, object: nil)
    }
}

extension Notification.Name {
    static let guyiSettingsChanged = Notification.Name("guyiSettingsChanged")
    static let guyiSentenceModeChanged = Notification.Name("guyiSentenceModeChanged")
    static let guyiSelectionLanguagesChanged = Notification.Name("guyiSelectionLanguagesChanged")
    static let guyiSelectionPauseChanged = Notification.Name("guyiSelectionPauseChanged")
}
