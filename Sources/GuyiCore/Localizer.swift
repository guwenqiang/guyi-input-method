import Foundation

public enum Localizer {
    public static func languageCode(preference: String, systemLanguages: [String] = Locale.preferredLanguages) -> String {
        let language = preference == "system" ? (systemLanguages.first ?? "en") : preference
        if language.lowercased().hasPrefix("zh") { return "zh-Hans" }
        if language.lowercased().hasPrefix("id") { return "id" }
        return "en"
    }
    public static var code: String {
        languageCode(preference: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "system")
    }
    public static func text(_ key: String) -> String {
        guard let path = Bundle.main.path(forResource: code, ofType: "lproj"), let bundle = Bundle(path: path) else { return key }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }
    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale(identifier: code), arguments: arguments)
    }
}
