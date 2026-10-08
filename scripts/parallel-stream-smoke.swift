import Foundation
import GuyiCore

@main
struct ParallelStreamSmoke {
    @MainActor static func main() async throws {
        var settings = TranslationSettings()
        settings.endpoint = "http://127.0.0.1:18973/v1"
        settings.source = .zh
        settings.enabledLanguages = [.en, .id]
        let session = TranslationSession()
        session.update(text: "测试", composing: false, settings: settings, apiKey: "local-test", immediate: true)
        try await Task.sleep(nanoseconds: 850_000_000)
        guard session.result == nil, session.selectableText(for: .en) == "Test", session.selectableText(for: .id) == nil else {
            fatalError("First language not independently selectable: \(session.status)")
        }
        print("PASS · English selectable before slower Indonesian response")
        try await Task.sleep(nanoseconds: 650_000_000)
        guard session.result?.en == "Test", session.result?.id == "Tes" else { fatalError(session.status) }
        print("PASS · Both independently validated responses merged")
    }
}
