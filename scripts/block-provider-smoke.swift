import Foundation
import GuyiCore

enum Keychain {
    enum ReadResult { case available(String), missing, locked, failed(Int32) }
}

@main
struct BlockProviderSmoke {
    static func main() async throws {
        guard let data = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings"),
              case .available(let key) = LocalCredential.readResult() else { print("BLOCKED · Local configuration unavailable"); return }
        let settings = try JSONDecoder().decode(TranslationSettings.self, from: data)
        let blocks = ["The delivery is tomorrow.", "Do not pay twice.", "Total: IDR 125,000."]
        for target in [Language.zh, .id] {
            let started = Date()
            do {
                let result = try await OpenAIBlockTranslator().translate(blocks, target: target, settings: settings, apiKey: key)
                print(String(format: "BATCH %@ · 3 regions · 1 request · %.2fs", target.rawValue, Date().timeIntervalSince(started)))
                for (index, text) in result.enumerated() { print(index, text) }
            } catch { print("FAIL", target.rawValue, error.localizedDescription) }
        }
    }
}
