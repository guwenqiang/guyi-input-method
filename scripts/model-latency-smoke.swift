import Foundation
import GuyiCore

enum Keychain {
    enum ReadResult { case available(String), missing, locked, failed(Int32) }
}

@main
struct ModelLatencySmoke {
    static func main() async throws {
        guard let data = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings"),
              case .available(let key) = LocalCredential.readResult() else { print("BLOCKED · Local configuration unavailable"); return }
        var settings = try JSONDecoder().decode(TranslationSettings.self, from: data)
        let models = [settings.model, "gpt-5.4-mini"]
        settings.source = .zh
        settings.enabledLanguages = [.en, .id]
        let cases = ["我还没付款，请不要再次扣款。", "请明天上午9:30确认订单AB-102，金额是125,000印尼盾。", "如果今天不能发货，请先告诉我，不要取消订单。"]
        for model in models {
            settings.model = model
            for (index, text) in cases.enumerated() {
                let started = Date()
                do {
                    let result = try await OpenAITranslator().translate(text, settings: settings, apiKey: key)
                    print(String(format: "MODEL %@ CASE %d %.2fs", model, index + 1, Date().timeIntervalSince(started)))
                    print("EN", result.en)
                    print("ID", result.id)
                    print("NOTE", result.note)
                } catch TranslationError.http(let status) {
                    print("FAIL", model, index + 1, "HTTP", status)
                    fflush(stdout)
                    if status == 429 { print("STOP · Rate limit or quota response; no further requests"); return }
                    if [400, 401, 403, 404].contains(status) { break }
                } catch { print("FAIL", model, index + 1, error.localizedDescription) }
                fflush(stdout)
            }
        }
    }
}
