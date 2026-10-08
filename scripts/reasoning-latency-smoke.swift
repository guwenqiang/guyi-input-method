import Foundation
import GuyiCore

enum Keychain {
    enum ReadResult { case available(String), missing, locked, failed(Int32) }
}

@main
struct ReasoningLatencySmoke {
    static func main() async throws {
        guard let data = UserDefaults(suiteName: "app.guyi.inputmethod.Guyi")?.data(forKey: "translationSettings"),
              case .available(let key) = LocalCredential.readResult() else {
            print("BLOCKED · Local configuration unavailable")
            return
        }
        var settings = try JSONDecoder().decode(TranslationSettings.self, from: data)
        if let marker = CommandLine.arguments.firstIndex(of: "--model"), marker + 1 < CommandLine.arguments.count {
            settings.model = CommandLine.arguments[marker + 1]
        }
        print("MODEL", settings.model)
        settings.source = .zh
        settings.enabledLanguages = [.en, .id]
        let cases = ["我还没付款，请不要再次扣款。", "请明天上午9:30确认订单AB-102，金额是125,000印尼盾。", "如果今天不能发货，请先告诉我，不要取消订单。"]
        var rejected = Set<String>()
        for (index, sample) in cases.enumerated() {
            if CommandLine.arguments.contains("--quick"), index > 0 { break }
            for effort in ["default", "none", "low"] where !rejected.contains(effort) {
                var request = try OpenAITranslator().request(sample, settings: settings, apiKey: key)
                if effort != "default" {
                    var body = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
                    body["reasoning"] = ["effort": effort]
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                }
                let started = Date()
                do {
                    let (responseData, response) = try await URLSession.shared.data(for: request)
                    guard let response = response as? HTTPURLResponse else { return }
                    guard (200..<300).contains(response.statusCode) else {
                        print("FAIL", effort, "HTTP", response.statusCode)
                        fflush(stdout)
                        if [401, 403, 429].contains(response.statusCode) { return }
                        rejected.insert(effort)
                        continue
                    }
                    let result = try OpenAITranslator.decode(responseData, languages: [.en, .id])
                    print(String(format: "CASE %d EFFORT %@ %.3fs", index + 1, effort, Date().timeIntervalSince(started)))
                    print("EN", result.en)
                    print("ID", result.id)
                    if let body = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                       let usage = body["usage"] as? [String: Any],
                       let details = usage["output_tokens_details"] as? [String: Any] {
                        print("REASONING TOKENS", details["reasoning_tokens"] ?? "unreported")
                    }
                } catch {
                    print("FAIL", effort, "network or response validation")
                    return
                }
                fflush(stdout)
            }
        }
    }
}
