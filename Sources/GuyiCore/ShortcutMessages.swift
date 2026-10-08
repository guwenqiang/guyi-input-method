import Foundation

public enum ShortcutMessages {
    public enum Hint: String { case notReady, disabled, unconfirmed, confirmed, addressOnly }
    public static let languages = ["zh-Hans", "zh-Hant", "en", "id", "ja", "ko", "es", "fr", "de", "pt", "ru", "ar", "hi", "th", "vi"]
    public static func language(preference: String, systemLanguages: [String] = Locale.preferredLanguages) -> String {
        let value = (preference == "system" ? systemLanguages.first ?? "en" : preference).lowercased().replacingOccurrences(of: "_", with: "-")
        if value.hasPrefix("zh") {
            return value.contains("hant") || value.hasPrefix("zh-tw") || value.hasPrefix("zh-hk") ? "zh-Hant" : "zh-Hans"
        }
        let base = String(value.split(separator: "-").first ?? "en")
        return languages.contains(base) ? base : "en"
    }
    private static func load(_ bundle: Bundle) -> [String: [String: String]] {
        guard let url = bundle.url(forResource: "shortcut-messages", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let values = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return values
    }
    private static let mainMessages = load(.main)
    public static func text(_ hint: Hint,
                            preference: String = UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system",
                            systemLanguages: [String] = Locale.preferredLanguages, bundle: Bundle = .main) -> String {
        let values = bundle.bundlePath == Bundle.main.bundlePath ? mainMessages : load(bundle)
        return values[language(preference: preference, systemLanguages: systemLanguages)]?[hint.rawValue]
            ?? values["en"]?[hint.rawValue]
            ?? {
                switch hint {
                case .notReady: return "Translation is not ready. Please wait."
                case .disabled: return "This translation language is not enabled."
                case .unconfirmed: return "Draft"
                case .confirmed: return "Text confirmed. Continue typing."
                case .addressOnly: return "Web addresses don't need translation."
                }
            }()
    }
}
