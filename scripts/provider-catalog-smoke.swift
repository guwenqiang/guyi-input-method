import Foundation
import GuyiCore

enum Keychain {
    enum ReadResult { case available(String), missing, locked, failed(Int32) }
}

@main
struct ProviderCatalogSmoke {
    static func main() async throws {
        guard let data = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings"),
              case .available(let key) = LocalCredential.readResult() else { print("BLOCKED · Local configuration unavailable"); return }
        let settings = try JSONDecoder().decode(TranslationSettings.self, from: data)
        print("CONFIGURED MODEL", settings.model)
        do {
            let models = try await ModelCatalog.fetch(settings: settings, apiKey: key)
            print("CATALOG COUNT", models.count)
            for model in models.filter({ $0.lowercased().contains("gpt") || $0.lowercased().contains("mini") || $0.lowercased().contains("flash") }).prefix(40) {
                print("MODEL", model)
            }
        } catch { print("FAIL · Model catalog", error.localizedDescription) }
    }
}
