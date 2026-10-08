import Foundation
import GuyiCore

@main
struct ProviderSmoke {
    static func main() async throws {
        guard let data = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings") else {
            print("SKIP · No saved provider configuration")
            return
        }
        var settings = try JSONDecoder().decode(TranslationSettings.self, from: data)
        guard case .available(let key) = LocalCredential.readResult() else { print("SKIP · No readable API key in GuYi local configuration"); return }
        settings.source = .zh
        let start = Date()
        let result = try await OpenAITranslator().stream("明天我再确认一下。", settings: settings, apiKey: key) { fields in
            print(String(format: "Preview %.2fs · %@", Date().timeIntervalSince(start), fields.keys.sorted().joined(separator: ",")))
        }
        print(String(format: "Complete %.2fs · %@", Date().timeIntervalSince(start), settings.model))
        print("EN: \(result.en)\nID: \(result.id)")
    }
}
