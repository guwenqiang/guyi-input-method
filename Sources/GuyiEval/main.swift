import Foundation
import GuyiCore

struct Case: Codable {
    let source: String
    let language: Language
    let mustPreserve: [String]
}

@main
struct GuyiEval {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count > 1 else {
            print("Usage: OPENAI_API_KEY=… guyi-eval Fixtures/translation-cases.json [model]")
            return
        }
        guard let key = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !key.isEmpty else {
            print("Missing OPENAI_API_KEY. No request sent.")
            exit(2)
        }
        let cases = try JSONDecoder().decode([Case].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        var settings = TranslationSettings()
        if arguments.count > 2 { settings.model = arguments[2] }
        var durations: [Double] = []
        var failures = 0
        for (index, sample) in cases.enumerated() {
            settings.source = sample.language
            let start = Date()
            do {
                let result = try await OpenAITranslator().translate(sample.source, settings: settings, apiKey: key)
                let duration = Date().timeIntervalSince(start)
                durations.append(duration)
                let preserved = sample.mustPreserve.allSatisfy { token in [result.zh, result.en, result.id].allSatisfy { $0.contains(token) } }
                let originalUnchanged = result.text(for: sample.language) == sample.source
                if !preserved || !originalUnchanged { failures += 1 }
                print("Case \(index + 1): \(preserved && originalUnchanged ? "PASS invariants" : "REVIEW") \(String(format: "%.2fs", duration))")
                print("ZH: \(result.zh)\nEN: \(result.en)\nID: \(result.id)\nNote: \(result.note)\n")
            } catch { failures += 1; print("Case \(index + 1): ERROR \(error.localizedDescription)") }
        }
        if !durations.isEmpty {
            let sorted = durations.sorted()
            print(String(format: "p50 %.2fs · p95 %.2fs · %d cases need review", sorted[(sorted.count - 1) / 2], sorted[min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.95)) - 1)], failures))
        }
        print("Invariant checks do not prove translation accuracy. Bilingual review is required for meaning, naturalness and grammar.")
        if failures > 0 { exit(1) }
    }
}
