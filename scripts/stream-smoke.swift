import Foundation
import GuyiCore

actor Observations {
    var first: Date?
    func record() { if first == nil { first = Date() } }
}

@main
struct StreamSmoke {
    static func main() async throws {
        var settings = TranslationSettings()
        settings.endpoint = "http://127.0.0.1:18973/v1"
        settings.source = .zh
        settings.enabledLanguages = [.en]
        let start = Date()
        let observations = Observations()
        let result = try await OpenAITranslator().stream("测试", settings: settings, apiKey: "local-test") { fields in
            if fields["en"] == "Test" { await observations.record() }
        }
        let end = Date()
        guard let first = await observations.first, end.timeIntervalSince(first) > 0.3, result.en == "Test", result.zh == "测试" else {
            fatalError("Stream did not emit early preview")
        }
        print(String(format: "PASS · Real HTTP SSE: first preview %.2fs, completion %.2fs", first.timeIntervalSince(start), end.timeIntervalSince(start)))
    }
}
