import Foundation
import GuyiCore

@main
struct ModelCatalogEmptySmoke {
    static func main() async {
        guard let saved = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings"),
              var settings = try? JSONDecoder().decode(TranslationSettings.self, from: saved),
              case .available(let key) = LocalCredential.readResult() else {
            print("BLOCKED · Local configuration unavailable")
            return
        }
        settings.model = ""
        do {
            let models = try await ModelCatalog.fetch(settings: settings, apiKey: key)
            print("MODEL_CATALOG_EMPTY_ID_SUCCESS true COUNT \(models.count)")
        } catch {
            print("MODEL_CATALOG_EMPTY_ID_SUCCESS false ERROR \(type(of: error))")
        }
    }
}
