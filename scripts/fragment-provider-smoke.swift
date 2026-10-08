import Foundation
import GuyiCore

enum Keychain {
    enum ReadResult { case available(String), missing, locked, failed(Int32) }
}

@main
struct FragmentProviderSmoke {
    static func main() async throws {
        guard let data = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings"),
              case .available(let key) = LocalCredential.readResult() else {
            print("BLOCKED · Provider configuration or local key unavailable")
            return
        }
        var settings = try JSONDecoder().decode(TranslationSettings.self, from: data)
        settings.source = .zh
        settings.enabledLanguages = [.en, .id]
        for text in ["你在", "你在哪里？"] {
            let started = Date()
            do {
                let result = try await OpenAITranslator().translate(text, settings: settings, apiKey: key)
                print(String(format: "Complete %.2fs", Date().timeIntervalSince(started)))
                print("SOURCE", text, "EN", result.en, "ID", result.id, "NOTE", result.note)
            } catch { print("FAIL ·", error.localizedDescription) }
        }
    }
}
