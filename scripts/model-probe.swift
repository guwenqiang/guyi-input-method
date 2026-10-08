import Foundation
import GuyiCore

enum Keychain {
    enum ReadResult { case available(String), missing, locked, failed(Int32) }
}

@main
struct ModelProbe {
    static func main() async throws {
        let defaults = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")!
        guard let data = defaults.data(forKey: "translationSettings") else { print("BLOCKED: no settings"); return }
        var settings = try JSONDecoder().decode(TranslationSettings.self, from: data)
        guard case .available(let key) = LocalCredential.readResult() else {
            print("BLOCKED: local GuYi credential configuration unavailable")
            return
        }
        settings.model = "gpt-4.1-mini"
        settings.source = .zh
        settings.enabledLanguages = [.en, .id]
        settings.timeoutSeconds = 15
        let start = Date()
        do {
            let result = try await OpenAITranslator().translate("请明天下午三点前确认订单。", settings: settings, apiKey: key)
            print(String(format: "PASS gpt-4.1-mini %.2fs", Date().timeIntervalSince(start)))
            print("EN: \(result.en)\nID: \(result.id)")
        } catch { print("FAIL gpt-4.1-mini: \(error.localizedDescription)") }
    }
}
