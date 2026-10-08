import AppKit
import GuyiCore
@MainActor
final class Preferences: ObservableObject {
    @Published private(set) var settings: TranslationSettings
    @Published private(set) var apiKey: String
    @Published private(set) var configured: Bool
    @Published private(set) var keyStatus = ""
    private let defaults: UserDefaults
    var inputLanguage: Language = .zh
    init(defaults: UserDefaults = .standard, readCredential: @escaping () -> LocalCredential.ReadResult = { LocalCredential.readResult() }) {
        self.defaults = defaults
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
        inputLanguage = settings.source == .auto ? .zh : settings.source
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
    func save(_ draft: TranslationSettings, key: String) async throws {
        if (draft.effectiveAPIProtocol != settings.effectiveAPIProtocol || draft.endpoint != settings.endpoint),
           key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw TranslationError.missingKey
        }
        _ = try draft.validatedURL()
        let encoded = try JSONEncoder().encode(draft)
        let newKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        try await ServiceProfiles.shared.remember(settings: settings, key: apiKey)
        try await ServiceProfiles.shared.remember(settings: draft, key: newKey.isEmpty ? apiKey : newKey)
        if !newKey.isEmpty && newKey != apiKey {
            try await Task.detached { try LocalCredential.save(newKey) }.value
        }
        defaults.set(encoded, forKey: "translationSettings")
        defaults.set(true, forKey: "configured")
        let previousLanguages = Set(settings.enabledLanguages ?? [.zh, .en, .id])
        let nextLanguages = Set(draft.enabledLanguages ?? [.zh, .en, .id])
        if !previousLanguages.subtracting(nextLanguages).isEmpty { TranslationCache.shared.clear() }
        if draft.source != settings.source, draft.source != .auto { inputLanguage = draft.source }
        settings = draft
        if !newKey.isEmpty { apiKey = newKey }
        if !apiKey.isEmpty { keyStatus = "" }
        configured = true
        TranslationCache.shared.configure(days: draft.effectiveCacheDays)
        HotwordStore.shared.configure(enabled: draft.hotwordsEnabled != false)
        ScreenshotService.shared.configure(enabled: false, key: draft.screenshotKey ?? 21,
            modifiers: draft.screenshotModifiers ?? 4352)
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
}
